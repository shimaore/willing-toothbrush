    chai = require 'chai'
    chai.should()

    describe 'The couchapp module', ->
      couchapp = require '../couchapp'
      it 'should return an object', ->
        couchapp.should.have.property '_id'
