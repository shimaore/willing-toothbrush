configure = (cfg) ->

  debug "Loading zones"

  zones = new Zones()

  debug 'Enumerate the domains listed in the database with a "records" field.'
  await cfg.prov
    .query "#{couchapp.id}/domains", include_docs:true
    .observe (rec) ->
      doc = rec.doc
      return if not doc?
      if doc.ENUM
        debug 'Ignoring ENUM document', doc
        return
      else
        zone = new Zone doc.domain, doc, cfg.serial
      zones.add_zone zone
      return

  debug 'Add any other records (hosts, ..)'
  await cfg.prov
    .query "#{couchapp.id}/names"
    .observe (rec) ->
      domain = rec.key
      return unless domain?
      zone = zones.get_zone(domain) ? zones.add_zone new Zone domain, {}
      zone.add_record rec.value
      return

  new_serial = get_serial()
  if new_serial > cfg.serial
    cfg.serial = new_serial
  else
    cfg.serial++

  debug 'Reload zones', serial: cfg.serial
  cfg.server.reload zones

  return

couchapp = require './couchapp'

install = (db) ->
  debug 'Installing application in database'
  {_rev} = await db.get(couchapp._id).catch -> {}
  couchapp._rev = _rev if _rev?
  await db.put couchapp

get_serial = ->
  now = new Date()
  date = parseInt now.toJSON().replace(/[^\d]/g,'').slice(0,8)
  seq = Math.floor(100*(now.getHours()*60+now.getMinutes())/1440)
  date*100+seq

main = ->
  cfg = {}

  assert process.env.DNS_PREFIX_ADMIN?, 'Please provide DNS_PREFIX_ADMIN'
  cfg.prov = new CouchDB process.env.DNS_PREFIX_ADMIN
  cfg.serial = "#{get_serial()}"
  cfg.web_port = process.env.DNS_WEB_PORT

  await install cfg.prov

  cfg.server = dns.createServer {}

  cfg.server.listen process.env.DNS_PORT ? 53

  debug 'Start monitoring changes'
  cfg.prov.changes
    live: true
    include_docs: true
    selector: $or: [ {type:'domain'}, {type:'host'} ]
    since: 'now'
  .observe ->
    configure cfg
  .catch (error) ->
    console.error error
    Promise.reject error

  debug 'Initial configuration'
  await configure cfg
  return

dns = require "./src/dns"
Zone = dns.Zone
Zones = dns.Zones

pkg = require './package.json'
debug = (require 'debug') pkg.name
assert = require 'assert'
CouchDB = require 'most-couchdb'

module.exports = {configure,main,install,get_serial}
if require.main is module
  debug 'Starting'
  main()
  .then ->
    debug 'Started'
  .catch (error) ->
    console.log error
    Promise.reject error
