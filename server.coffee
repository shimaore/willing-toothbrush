configure = (cfg) ->

  debug "Loading zones"

  zones = new Zones()

  debug 'Enumerate the domains listed in the database with a "records" field.'
  rows = cfg.prov.queryAsyncIterable couchapp.id, 'domains', include_docs:true

  for await rec from rows
    do (rec) ->
      doc = rec.doc
      return if not doc?
      if doc.ENUM
        debug 'Ignoring ENUM document', doc
        return
      else
        debug 'new Zone', cfg.serial, JSON.stringify doc
        zone = new Zone doc.domain, doc, cfg.serial
      zones.add_zone zone
      return

  debug 'Add any other records (hosts, ..)'
  rows = cfg.prov.queryAsyncIterable couchapp.id, 'names'

  for await rec from rows
    do (rec) ->
      domain = rec.key
      return unless domain?
      debug 'add record', domain, JSON.stringify rec.value
      zone = zones.get_zone(domain) ? zones.add_zone new Zone domain, {}
      zone.add_record rec.value
      return

  new_serial = get_serial()
  if new_serial > cfg.serial
    cfg.serial = new_serial
  else
    cfg.serial++

  debug 'Reload zones', serial: cfg.serial
  cfg.server4.reload zones
  cfg.server6.reload zones

  return

couchapp = require './couchapp'

install = (db) ->
  debug 'Installing application in database'
  try
    await db.update couchapp
    true
  catch
    false

get_serial = ->
  now = new Date()
  date = parseInt now.toJSON().replace(/[^\d]/g,'').slice(0,8)
  seq = Math.floor(100*(now.getHours()*60+now.getMinutes())/1440)
  date*100+seq

main = ->
  debug 'Main'
  cfg = {}

  assert process.env.DNS_PREFIX_ADMIN?, 'Please provide DNS_PREFIX_ADMIN'
  cfg.prov = new CouchDB process.env.DNS_PREFIX_ADMIN
  cfg.serial = get_serial()

  await install cfg.prov

  debug 'Create server'
  cfg.server4 = dns.createServer 'udp4', new Zones()
  cfg.server6 = dns.createServer 'udp6', new Zones()

  debug 'Initial configuration'
  await configure cfg

  port = parseInt process.env.DNS_PORT
  port = 53 if isNaN port
  cfg.server4.port = port
  # cfg.server4.listen()
  cfg.server6.port = port
  cfg.server6.listen()

  debug 'Start monitoring changes'
  needs_reconfigure = false

  cfg.prov.changes
    live: true
    # selector: $or: [ {type:'domain'}, {type:'host'} ] # only on CouchDB2
    since: 'now'
  .filter ({id}) ->
    id.match /^(domain|host):/
  .observe ({id}) ->
    debug "Reconfiguring due to #{id}"
    needs_reconfigure = true
    return
  .catch (error) ->
    console.error 'Monitoring changes:', error
    process.exit 1

  setInterval ->
    do ->
      try
        return unless needs_reconfigure
        await configure cfg
        needs_reconfigure = false
      catch error
        console.error 'reconfigure', error
  , 60*1000

  return [cfg.server4.statistics,cfg.server6.statistics]

{Zone,Zones} = dns = require "./src/dns"

pkg = require './package.json'
debug = (require 'tangible') pkg.name
assert = require 'assert'
CouchDB = require 'most-couchdb/with-update'

module.exports = {configure,main,install,get_serial}
if require.main is module
  debug 'Starting'
  do ->
    try
      console.log 'Starting'
      [statistics4,statistics6] = await main()
      console.log 'Started'
    catch error
      console.error 'Main failed', error
      process.exit 1
    setInterval ->
      debug 'Requests', statistics4.requests.toString(10), statistics6.requests.toString(10)
    , 30*1000
    return
