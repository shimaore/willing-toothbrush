    chai = require 'chai'
    chai.should()

    describe 'Modules', ->
      it 'should load', ->
        for module in ['../server','../src/dns','../src/ndns','../src/shuffle']
          require module


    describe 'get_serial', ->
      {get_serial} = require '../server'
      it 'should return a number', ->
        get_serial().should.be.a 'Number'

      it 'should be above 2015010100', ->
        get_serial().should.be.above 2015010100

    describe 'undotize', ->
      {undotize} = require '../src/dns'
      (undotize 'a' ).should.eql 'a'
      (undotize 'a.').should.eql 'a'
    describe 'dotize', ->
      {dotize} = require '../src/dns'
      (dotize 'a' ).should.eql 'a.'
      (dotize 'a.').should.eql 'a.'
