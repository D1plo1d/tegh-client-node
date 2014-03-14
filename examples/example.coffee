tegh = require("../lib/index.js")
util = require("./util")
_ = require("lodash")

user = process.argv[2]
user = null if user == "--add-cert"
addCert = false
addCert ||= (arg == "--add-cert") for arg in process.argv[2..]
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
  console.log "DNS-SD Tegh advertisement found on #{service.address}."
  tegh.discovery.stop()
  service.user = user
  service.password = password
  service.addCert = addCert
  client = new tegh.Client(service)
  .on("initialized", onInit)
  .on("error", onError)
  .on("change", onChange)

onServiceDown = ->
  console.log "down"

onError = (e) ->
  console.log "Error!"
  if client.unauthorized
    console.log "\nUnauthorized. Try this:\n"
    console.log "  coffee example.coffee [USER]\n"
  else if !client.isKnownHost
    console.log "\nUnrecognized SSL Cert. This may be a result of hackers.\n"
    console.log "If this is your first time connecting and you are not terribly"
    console.log "concerned with security try this:\n"
    console.log "  coffee example.coffee --add-cert\n"
  else
    throw e
  process.exit()

onInit = ->
  console.log "Your 3D printer is now connect.\n"

onChange = ->
  heater = _.find(client.data, type: 'heater')
  process.stdout.write "\rTemperature of first extruder/bed: #{heater.current_temp}   "
