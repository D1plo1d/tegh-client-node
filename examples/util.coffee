stdin = process.openStdin()
tty = require('tty')

module.exports =
# Get a password from the console, printing stars while the user types
  get_password: (cb) ->
    process.stdin.resume()
    process.stdin.setEncoding "utf8"
    process.stdin.setRawMode true
    password = ""
    process.stdin.on "data", (char) ->
      char = char + ""
      switch char
        when "\n", "\r", "\u0004"

          # They've finished typing their password
          process.stdin.setRawMode false
          stdin.pause()
          console.log ""
          cb password
        when "\u0003"

          # Ctrl C
          console.log "Cancelled"
          process.exit()
        else

          # More passsword characters
          process.stdout.write "*"
          password += char

    return

  getBoolean: (cb) ->
    process.stdin.resume()
    process.stdin.setEncoding "utf8"
    process.stdin.setRawMode true
    process.stdin.on "data", (char) ->
      char = char + ""
      switch char
        when "y", "Y"
          return cb true
        when "n", "N"
          return cb false
        when "\u0003"
          # Ctrl C
          console.log "Cancelled"
          process.exit()

    return
