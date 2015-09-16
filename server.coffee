seem = require 'seem'

configure = seem (db,server) ->

  debug "Loading zones"

  zones = new Zones()

  # Enumerate the domains listed in the database with a "records" field.
  {rows} = yield db.query "#{couchapp.id}/domains", include_docs:true

  for rec in rows ? []
    do (rec) ->
      doc = rec.doc
      return if not doc?
      if doc.ENUM
        debug 'Ignoring ENUM document', doc
        return
      else
        zone = new Zone doc.domain, doc
      zones.add_zone zone

  # Add any other records (hosts, ..)
  {rows} = yield db.query "#{couchapp.id}/names"

  for rec in rows ? []
    do (rec) ->
      domain = rec.key
      return unless domain?
      zone = zones.get_zone(domain) ? zones.add_zone new Zone domain, {}
      zone.add_record rec.value

  server.reload zones

  return

couchapp = require './couchapp'

install = seem (db) ->
  yield update db, couchapp

main = ->
  cfg = {}

  assert process.env.DNS_PREFIX_ADMIN?, 'Please provide DNS_PREFIX_ADMIN'
  cfg.prov = new PouchDB process.env.DNS_PREFIX_ADMIN

  install cfg.prov

  server = dns.createServer()

  server.listen process.env.DNS_PORT ? 53

  monitor = ->
    changes = cfg.prov.changes
      live: true
      include_docs: true
      filter: "#{couchapp.id}/changes"
      since: 'now'

    changes.on 'change', ->
      configure cfg.prov, server

    changes.on 'error', (err) ->
      debug "Changes error: #{err}"
      monitor()

  # Start monitoring changes
  monitor()

  # Initial configuration
  configure cfg.prov, server
  return

dns = require "./src/dns"
Zone = dns.Zone
Zones = dns.Zones

pkg = require './package.json'
debug = (require 'debug') pkg.name
assert = require 'assert'
PouchDB = require 'pouchdb'
update = require 'nimble-direction/update'

module.exports = {configure,main,install}
if require.main is module
  main()
