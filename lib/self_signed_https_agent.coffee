tls  = require "tls"
https = require "https"
http = require "http"
net = require "net"
_ = require "lodash"

# This HTTPS Agent allows us to verify a server's self-signed cert before
# accepting the connection via a "cert" event that is emitted when the cert
# is received.
module.exports = class SelfSignedHttpsAgent extends https.Agent

  constructor: (options = {}) ->
    super(_.merge options, rejectUnauthorized: false)
    # Preventing super from overriding functions
    @createConnection = SelfSignedHttpsAgent.prototype.createConnection
    @getName = SelfSignedHttpsAgent.prototype.getName

  createConnection: (port, host, options) ->
    cleartextStream = tls.connect(port, host, options)
    # console.log cleartextStream.socket
    cb = _.partial @_validatePeerCertificate, cleartextStream
    cleartextStream.on("secureConnect", cb)

  getName: ->
    "#{super.getName()}:tegh"

  _validatePeerCertificate: (cleartextStream) =>
    cert = cleartextStream.getPeerCertificate()
    @emit("cert", cert)

