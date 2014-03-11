dgram = require('dgram')
dns = require('native-dns')
UDPSocket = require('native-dns/lib/utils').UDPSocket
DnsPacket = require('native-dns/lib/packet')
consts = require('native-dns-packet/consts')
util = require('util')
net = require('net')
_ = require('lodash')
EventEmitter = require('events').EventEmitter

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
    @services = []

  start: ->
    @makeAllMdnsRequests()
    @mdnsInterval = setInterval(@makeAllMdnsRequests, 25)
    return @

  makeAllMdnsRequests: =>
    @_sockets = []
    for type, address of @multicastAddresses
      @_makeMdnsRequest type, address
    setTimeout(_.partial(@_close, @_sockets), 2000)

  _makeMdnsRequest: (type, address) =>
    server =
      port: @mdnsServer.port
      type: @mdnsServer.type
      address: address
    question = dns.Question @dnsSdOpts
    dg = dgram.createSocket(type)
    socket = new UDPSocket dg, server

    req = dns.Request
      question: question
      server: server
      timeout: 2000

    packet = new DnsPacket(socket)
    packet.timeout = 2000
    packet.header.id = random_integer()
    packet.header.rd = 1
    packet.answer = []
    packet.additional = []
    packet.authority = []
    packet.question = [req.question]

    dg.on "message", @_onMessage

    packet.send()
    dg.ref()
    @_sockets.push dg

  _close: (sockets) =>
    for socket in sockets
      socket.unref()
      socket.close()
    # console.log "Closing the MDNS discovery udp connections"

  stop: =>
    clearInterval @mdnsInterval
    @removeAllListeners
    for service in @services
      clearTimeout service.staleTimeout if service.staleTimeout?
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
      serviceName = service.data.split(".")[0].replace /\s\(\d+\)/, ""
      @_updateService
        address: rinfo.address
        hostname: null
        serviceName: serviceName
        path: "/printers/#{serviceName}/"

  _updateService: (service) =>
    # console.log service
    isSameFn = _.partial @_isSameService, service
    preExistingService = _.first(@services, isSameFn)[0]
    return @_updateTimeout preExistingService if preExistingService?
    @services.push service
    @_updateTimeout service
    @emit "serviceUp", service

  _isSameService: (e1, e2) ->
    e2.serviceName == e1.serviceName and e2.address == e1.address

  _removeService: (service) =>
    _.remove @services, _.partial(@_isSameService, service)
    @emit "serviceDown", service

  _updateTimeout: (service) ->
    clearTimeout service.staleTimeout if service.staleTimeout?
    service.staleTimeout = setTimeout(_.partial(@_removeService, service), 1000)
