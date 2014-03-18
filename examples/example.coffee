tegh = require("../lib/index.js")
util = require("./util")
_ = require("lodash")

user = process.argv[2]
client = null
password = null

setImmediate ->
  if user?
    process.stdout.write "Password: "
    util.get_password (p) ->
      password = p
      startListening()
  else
    startListening()

startListening = ->
  console.log "\nlistening for DNS-SD Tegh advertisements..."
  tegh.discovery
  .once("serviceUp", onServiceUp)
  .on("serviceDown", onServiceDown)
  .start()

onServiceUp = (service) ->
  console.log "DNS-SD Tegh advertisement found on #{service.address}. " +
  "Connecting..."
  tegh.discovery.stop()
  service.user = user
  service.password = password
  client = new tegh.Client(service)
  .on("initialized", onInit)
  .on("error", onError)
  .on("change", onChange)

onServiceDown = ->
  console.log "down"

onError = (e) ->
  console.log "Error!\n"
  if client.unauthorized
    console.log "\nUnauthorized. Try this:\n"
    console.log "  coffee example.coffee [USER]\n"
    process.exit()
  else if client.knownName and !client.knownCert
    console.log "The SSL Cert on your 3D printer has changed. This may be a "
    console.log "result of l33t hax0rs.\n"
    process.exit()
  else if !client.knownName and !client.knownCert
    console.log "You are attempting to connect to a new printer that has "
    console.log "with an untrusted SSL certificate.\n"
    console.log "Do not connect to this printer unless you are on a network"
    console.log "you absolutely trust.\n"
    console.log "SSL Fingerprint:\n"
    console.log client.cert.modulus
    console.log "\nWould you like to connect anyways? (y/n)"
    util.getBoolean (val) ->
      console.log if val then "y" else "n"
      return process.exit() unless val
      client.opts.cert = client.cert
      onServiceUp client.opts
  else
    throw e

onInit = ->
  console.log "Your 3D printer is now connect.\n"

onChange = ->
  heater = _.find(client.data, type: 'heater')
  process.stdout.write "\rTemperature of first extruder/bed: #{heater.current_temp}   "
