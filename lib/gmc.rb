require 'termios'
require 'fcntl'

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
    return gmc if gmc.version

    raise "Couldn't open device"
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
    @tty.write "<SPIR"
    @tty.write [0, 0, 0, (2047 >> 8) & 0xff, (2047 >> 0) & 0xff].pack('C5')
    @tty.write ">>"
    while IO.select [@tty], nil, nil, 5
      p @tty.read(1)
    end
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

gmc = GMC.open '/dev/tty.wchusbserial1420'
p gmc.datetime
