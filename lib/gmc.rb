require 'termios'
require 'fcntl'
require 'strscan'

class GMC
  class TTY
    include Termios

    def self.open filename, speed, mode
      if mode =~ /^(\d)(\w)(\d)$/
        t.data_bits = $1.to_i
        t.stop_bits = $3.to_i
        t.parity = { 'N' => :none, 'E' => :even, 'O' => :odd }[$2]
        t.speed = speed
        t.read_timeout = 5
        t.reading = true
        t.update!
      end
    end

    def self.data_bits t, val
      t.cflag &= ~CSIZE               # clear previous values
      t.cflag |= const_get("CS#{val}") # Set the data bits
      t
    end

    def self.stop_bits t, val
      case val
      when 1 then t.cflag &= ~CSTOPB
      when 2 then t.cflag |= CSTOPB
      else
        raise
      end
      t
    end

    def self.parity t, val
      case val
      when :none
        t.cflag &= ~PARENB
      when :even
        t.cflag |= PARENB  # Enable parity
        t.cflag &= ~PARODD # Make it not odd
      when :odd
        t.cflag |= PARENB  # Enable parity
        t.cflag |= PARODD  # Make it odd
      else
        raise
      end
      t
    end

    def self.speed t, speed
      t.ispeed = const_get("B#{speed}")
      t.ospeed = const_get("B#{speed}")
      t
    end

    def self.read_timeout t, val
      t.cc[VTIME] = val
      t.cc[VMIN] = 0
      t
    end

    def self.reading t
      t.cflag |= CLOCAL | CREAD
      t
    end
  end

  def self.open filename, speed = 115200
    f = File.open filename, File::RDWR|Fcntl::O_NOCTTY|Fcntl::O_NDELAY
    f.sync = true

    # enable blocking reads, otherwise read timeout won't work
    f.fcntl Fcntl::F_SETFL, f.fcntl(Fcntl::F_GETFL, 0) & ~Fcntl::O_NONBLOCK

    t = Termios.tcgetattr f
    t = TTY.data_bits    t, 8
    t = TTY.stop_bits    t, 1
    t = TTY.parity       t, :none
    t = TTY.speed        t, speed
    t = TTY.read_timeout t, 5
    t = TTY.reading      t

    Termios.tcsetattr f, Termios::TCSANOW, t
    Termios.tcflush f, Termios::TCIOFLUSH

    gmc = new f

    # Try reading the version a few times before giving up
    gmc.flush
    2.times { gmc.version }
    return gmc if gmc.version

    raise "Couldn't open device"
  end

  class SampleInfo
    def initialize count_frequency, sample_frequency
      @count_frequency  = count_frequency
      @sample_frequency = sample_frequency
    end

    def calc_sample_time start, offset
      start + (offset * @sample_frequency)
    end
  end

  class CPS < SampleInfo
    def initialize
      super(1, 1)
    end

    def to_cpm val
      node = val
      count = 0
      60.times do
        break unless node
        count += node.count
        node = node.prev
      end
      count
    end

    def to_cps val
      val.count
    end
  end

  class CPM < SampleInfo
    def initialize sample_frequency
      super(60, 1)
    end

    def to_cpm val
      val
    end

    def to_cps val
      nil
    end
  end

  class Sample
    attr_reader :prev, :count
    attr_accessor :next

    include Enumerable

    def initialize start_time, offset, count, info, prev
      @start_time = start_time
      @offset     = offset
      @count      = count
      @info       = info
      @prev       = prev
      @next       = nil
      @cpm        = nil
    end

    def each
      n = self
      while n
        yield n
        n = n.next
      end
    end

    def cpm
      return @cpm if @cpm
      @cpm = @info.to_cpm self
    end

    def cps
      @info.to_cps self
    end

    # uSv / h
    def uSv
      # Apparently for the GMC-320+, 200 cpm = 1.0 uSv / h
      # https://www.gqelectronicsllc.com/forum/topic.asp?TOPIC_ID=4037
      cpm / 200.0
    end

    def to_ary
      sample_time = @info.calc_sample_time @start_time, @offset
      [sample_time, cps, cpm, uSv]
    end
  end

  CPS_PS = CPS.new      # count per sec, recorded each sec
  CPM_PM = CPM.new 60   # count per min, recorded each min
  CPM_PH = CPM.new 3600 # count per min, recorded each hr

  def self.parse_history data
    buf     = StringScanner.new data
    head    = nil
    samples = nil

    while !buf.eos?
      byte = buf.get_byte
      case byte
      when 'U'.b
        if buf.peek(1) == "\xAA".b
          # Some kind of command
          buf.get_byte
          x = buf.get_byte
          case x
          when "\x00".b # date / timestamp + history type
            time = 6.times.map { buf.get_byte.ord }
            time[0] += 2000
            last_time = Time.mktime(*time)
            offset    = 0
            _55, _AA, history_type = *3.times.map { buf.get_byte }
            if _55 == "\x55".b && _AA == "\xAA".b
              sample_info = case history_type.ord
                            when 1
                              CPS_PS
                            when 2
                              CPM_PM
                            when 3
                              CPM_PH
                            else
                              raise "Unknown history type: %d" % [history_type.ord]
                            end
            else
              raise "format error"
            end
          when "\x01".b # double byte sample (sample that exceeds 255)
            raise "big"
          else
            raise "Unkown command %d" % x.bytes
          end
        end
      when "\xFF".b
      else
        offset += 1
        samples = Sample.new(last_time, offset, byte.ord, sample_info, samples)
        if samples.prev
          samples.prev.next = samples
        end
        head ||= samples
      end
    end
    head
  end

  def initialize tty
    @tty = tty
  end

  # Get hardware model and version
  def version
    @tty.write "<GETVER>>"
    @tty.read 14
  end

  # Get current CPM value
  def cpm
    @tty.write "<GETCPM>>"
    h, l = @tty.read(2).unpack 'CC'
    (h << 8) + l
  end

  # Stops the heartbeat
  def stop_heartbeat
    @tty.write "<HEARTBEAT0>>"
  end

  # Yields count per second to the block every second
  def heartbeat
    @tty.write "<HEARTBEAT1>>"
    loop do
      IO.select [@tty]
      h, l = @tty.read(2).unpack 'CC'
      yield ((h & 0xf) << 8) + l
    end
  end

  def voltage
    @tty.write "<GETVOLT>>"
    @tty.read(1).unpack('C').first / 10.0
  end

  def history
    # https://www.gqelectronicsllc.com/forum/topic.asp?TOPIC_ID=4445

    buf = ''.b

    (0..0x0F0000).step(0x1000).each do |i|
      @tty.write "<SPIR"
      z = [(0xFF0000 & i) >> 16, (0x00FF00 & i) >> 8, 0x0000FF & i]
      @tty.write z.pack('C3')
      @tty.write [0x0f, 0xff].pack('C2')
      @tty.write ">>"
      buf_slice = @tty.read 4096

      if buf_slice.nil? || buf_slice.empty?
        $stderr.puts "retrying"
        return self.history
      else
        if buf_slice.bytes.all? { |byte| byte == 255 }
          $stderr.puts "FINISHED"
          break
        else
          buf << buf_slice
        end
      end
    end

    if buf.empty?
      self.history
    else
      buf
    end
  end

  def samples
    GMC.parse_history history
  end

  def serial
    @tty.write "<GETSERIAL>>"
    @tty.read(7)
  end

  def poweroff
    @tty.write "<POWEROFF>>"
  end

  # Refresh configuration
  def cfgupdate
    @tty.write "<CFGUPDATE>>"
    @tty.read 1
  end

  [ [:year,   'YY'],
    [:month,  'MM'],
    [:day,    'DD'],
    [:hour,   'HH'],
    [:minute, 'MM'],
    [:second, 'SS'] ].each do |m, s|
    define_method("#{m}=") { |val|
      @tty.write "<SETTIME" + s + [val].pack("C") + ">>"
      @tty.read 1
    }
  end

  def factory_reset
    @tty.write "<FACTORYRESET>>"
  end

  def reboot
    @tty.write "<REBOOT>>"
  end

  def datetime= val
    yy = val.year - 2000
    mm = val.month
    dd = val.day
    hh = val.hour
    m  = val.min
    ss = val.sec
    @tty.write "<SETDATETIME"
    @tty.write [yy, mm, dd, hh, m, ss].pack("C6")
    @tty.write ">>"
    @tty.read 1
  end

  def datetime
    @tty.write "<GETDATETIME>>"
    yy, mm, dd, hh, m, ss, = @tty.read(7).unpack 'C7'
    Time.new yy + 2000, mm, dd, hh, m, ss
  end

  def temp
    @tty.write "<GETTEMP>>"
    int, dec, neg, = @tty.read(4).unpack('C4')
    (int + (dec / 10.0)) * (neg == 0 ? 1 : -1)
  end

  def gyro
    @tty.write "<GETGYRO>>"
    x, xx, y, yy, z, zz, = @tty.read(7).unpack('C7')
    {
      x: (x << 8) + xx,
      y: (y << 8) + yy,
      z: (z << 8) + zz,
    }
  end

  def poweron
    @tty.write "<POWERON>>"
  end

  def flush
    Termios.tcflush @tty, Termios::TCIOFLUSH
  end
end

if __FILE__ == $0
  gmc = GMC.open ARGV[0] || '/dev/tty.wchusbserial14130'
  print gmc.history
end
