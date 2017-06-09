# gmc

* https://github.com/tenderlove/gmc

## DESCRIPTION:

Serial interface to GMC (Geiger Muller Counter) from GQ electronics.

## SYNOPSIS:

Dump all history as CSV

```ruby
require 'csv'
require 'gmc'

gmc = GMC.open ARGV[0] || '/dev/tty.wchusbserial14130'

CSV do |csv|
  csv << %w{ time cps cpm uSv }
  gmc.samples.each { |s| csv << s.to_ary }
end
```

## REQUIREMENTS:

* gem install ruby-termios

## INSTALL:

* FIX (sudo gem install, anything else)

## LICENSE:

(The MIT License)

Copyright (c) 2016 Aaron Patterson

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
