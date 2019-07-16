#
# Based on appload/dns
# with async loading
# and other changes for ccnq3
#
dgram = require('dgram')
ndns = require('./ndns')
shuffle = require './shuffle'

dotize = (domain) ->
  if domain[-1..] == "." then domain else domain + "."

undotize = (domain) ->
  if domain[-1..] != "." then domain else domain[..-2]

{isArray} = Array

isEmpty = (o) -> Object.entries(o).length is 0

exports.Zone = class Zone

  constructor: (domain, options,@serial) ->
    @domain = undotize(domain)
    @dot_domain = dotize(domain)
    @set_options(options)
    @records = (@create_record(record) for record in options.records or [])
    @select_class "SOA"
    .forEach (d) =>
      soa = @_soa()
      if d.length is 0
        @records.push soa
        return
      d.value = soa.value

  _soa: ->
    keys = "soa admin serial refresh retry expire min_ttl"
    value = keys.split(" ").map((param) => @[param]).join(" ")
    {name: @dot_domain, @ttl, class: "SOA", value}

  add_record: (record) ->
    @records.push @create_record record

  defaults: ->
    soa: @dot_domain
    ttl: 420
    refresh: 840         # refresh (30 minutes)
    retry: 900           # retry (15 minutes)
    expire: 1209600      # expire (2 weeks)
    min_ttl: 1200        # minimum TTL (20 minutes)
    admin: "hostmaster.#{@domain}."

  record_defaults: ->
    ttl: @ttl or @defaults().ttl
    class: "A"
    value: ""

  set_options: (options) ->
    defaults = @defaults()
    for key, val of defaults
      @[key] = options[key] or val

    @admin = dotize(@admin)

  create_record: (record) ->
    r = Object.assign {}, @record_defaults(), record
    r.name = if r.prefix? then dotize(r.prefix) + @dot_domain else @dot_domain
    r

  select_class: (type) ->
    @records.filter (record) -> record.class == type

  select: (type, name) ->
    name = name.toLowerCase()
    @records.filter (record) -> (record.class == type) and (record.name == name)

class Response
  constructor: (@server) ->
    @answer = []
    @authoritative = []
    @additional = []
    #TODO response record limit 18

  add: (obj, to) ->
    if obj? and not isEmpty(obj)
      if isArray obj
        for o in obj
          to.push o
      else
        to.push obj
      true
    else
      false

  add_answer: (record) ->
    @add(record, @answer)

  add_authoritative: (record) ->
    @add(record, @authoritative)

  add_additional: (record) ->
    @add(record, @additional)

  add_ns_records: (zone) ->
    zone
    .select_class "NS"
    .forEach (d) => @add_authoritative shuffle d

  add_additionals: ->
    [@answer..., @authoritative...].forEach (record) =>
      name = dotize record.value
      # Only do the resolution for explicit names (e.g. CNAME, NS)
      return unless typeof name is 'string'
      zone = @server.zones?.find_zone name
      # Nothing to add if we don't know about that zone.
      return unless zone?

      zone
      .select "A", name
      .forEach (d) => @add_additional shuffle d
      zone
      .select "AAAA", name
      .forEach (d) => @add_additional shuffle d
    return

  add_soa_to_authoritative: (zone) ->
    zone
    .select_class "SOA"
    .forEach (d) => @add_authoritative d

  resolve: (name,type,zone) ->
    name = dotize name

    # If a CNAME answer is available, always provide it.
    cnames = zone.select "CNAME", name

    if cnames.length > 0
      cnames.forEach (d) ->
        if @add_answer d
          @add_additionals()
      return

    # No CNAME, lookup record
    zone
    .select type, name
    .forEach (d) =>
      if type is 'NS' or type is 'A' or type is 'AAAA'
        shuffle d
      if @add_answer d
        if type isnt "NS"
          @add_ns_records zone
        @add_additionals()
      else
        # empty response, SOA in authoritative section
        @add_soa_to_authoritative zone
    return

  commit: (req, res) ->
    res.setHeader {
      id: req.header.id
      qr: 1 # response
      ra: 0 # recursion available
      rd: 0 # recursion desired
      aa: 1 # authoritative
      qdcount: req.q.length
      ancount: @answer.length
      nscount: @authoritative.length
      arcount: @additional.length
    }

    for q in req.q
      res.addQuestion(q)

    for record in [@answer..., @authoritative..., @additional...]
      value = if isArray(record.value) then record.value else record.value.split " "
      res.addRR record.name, record.ttl, "IN", record.class, value...
    return

exports.Zones = class Zones

  constructor: ->
    @__zones = {}

  # Explicit: add_zone returns the zone
  add_zone: (zone) ->
    @__zones[zone.dot_domain] = zone

  find_zone: (domain) ->
    domain = dotize domain.toLowerCase()
    if @__zones[domain]?
      return @__zones[domain]
    else
      if domain is '.'
        return
      else
        return @find_zone domain.split(".")[1...].join(".")

  get_zone: (domain) ->
    domain = dotize domain
    @__zones[domain]

class DNS

  constructor: (zones) ->
    @server = ndns.createServer('udp4')
    @server.on 'request', @resolve.bind this
    @port or= 53
    @reload zones

    @statistics =
      requests: `0n`

  reload: (zones) ->
    @__zones = zones

  listen: (port) ->
    @server.bind port or @port

  resolve: (req, res) ->
    @statistics.requests++

    response = new Response this

    for q in req.q
      name = q.name
      type = q.typeName
      if zone = @__zones?.find_zone name
        response.resolve name, type, zone

    response.commit(req, res)
    res.send()

  close: ->
    @server.close()

exports.createServer = (zones) ->
  new DNS zones
exports.dotize = dotize
exports.undotize = undotize
