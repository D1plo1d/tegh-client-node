dgram = require('dgram')
dns = require('native-dns')
UDPSocket = require('native-dns/lib/utils').UDPSocket
DnsPacket = require('native-dns/lib/packet')
consts = require('native-dns-packet/consts')
util = require('util')
net = require('net')
_ = require('lodash')
EventEmitter = require('events').EventEmitter
certs = require('./certs')

`var random_integer = function() {
  return Math.floor(Math.random() * 50000 + 1);
};`


module.exports = class DnsSd extends EventEmitter
  multicastAddresses:
    udp4: "224.0.0.251"
    # udp6: "FF02::FB"
  mdnsServer:
    port: 5353
    type: "udp"

  dnsSdOpts:
    name: "_tegh._tcp.local"
    type: "PTR"

  constructor: (@filter) ->
    @_knownHosts = certs.knownHosts()
    @services = []
    @_connections = []

  start: ->
    @stop()
    @_openSocket(type, address) for type, address of @multicastAddresses
    @makeAllMdnsRequests()
    @mdnsInterval = setInterval(@makeAllMdnsRequests, 500)
    return @

  makeAllMdnsRequests: =>
    @_makeMdnsRequest connection for connection in @_connections
    # setTimeout(_.partial(@_close, @_connections), 2000)

  _openSocket: (type, address) =>
    server =
      port: @mdnsServer.port
      type: @mdnsServer.type
      address: address
    dg = dgram.createSocket(type)
    socket = new UDPSocket dg, server
    dg.on "message", @_onMessage
    dg.ref()
    @_connections.push socket: socket, server: server, dg: dg


  _makeMdnsRequest: (connection) =>
    question = dns.Question @dnsSdOpts

    req = dns.Request
      question: question
      server: connection.server
      timeout: 2000

    packet = new DnsPacket(connection.socket)
    packet.timeout = 2000
    packet.header.id = random_integer()
    packet.header.rd = 1
    packet.answer = []
    packet.additional = []
    packet.authority = []
    packet.question = [req.question]

    packet.send()

  stop: =>
    clearInterval @mdnsInterval
    @removeAllListeners
    for service in @services
      clearTimeout service.staleTimeout if service.staleTimeout?
    for connection in @_connections
      connection.dg.unref()
      connection.dg.close()
    @_connections = []
    @services = []
    return @

  _onMessage: (buffer, rinfo) =>
    return if net.isIPv6 rinfo.address
    packet = DnsPacket.parse(buffer)
    # console.log event

    for service in packet.answer
      # This would add ipv6 if we supported it:
      # event.address = service.address if service.type == 28
      continue unless service.class == 1 and service.type == 12
      continue unless service.data?
      name = service.data.split(".")[0].replace /\s\(\d+\)/, ""
      @_updateService
        address: rinfo.address
        hostname: null
        name: name
        path: "/printers/#{name}/"

  _updateService: (service) =>
    # console.log service
    isSameFn = _.partial @_isSameService, service
    preExistingService = _.first(@services, isSameFn)[0]
    return @_updateTimeout preExistingService if preExistingService?
    service.knownName = _.find(@_knownHosts, printer: service.name)?
    @services.push service
    @_updateTimeout service
    @emit "serviceUp", service

  _isSameService: (e1, e2) ->
    e2.name == e1.name and e2.address == e1.address

  _removeService: (service) =>
    _.remove @services, _.partial(@_isSameService, service)
    @emit "serviceDown", service

  _updateTimeout: (service) ->
    clearTimeout service.staleTimeout if service.staleTimeout?
    service.staleTimeout = setTimeout(_.partial(@_removeService, service), 1000)
