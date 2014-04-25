should = require 'should'
Record = require '../lib'

describe 'Nohm model should be extended', ->

  it 'when it was extended by record', (done) ->

      Record.configure
        redis: require('redis').createClient()

      Record.model 'ExtendedModel',
        properties:
          name:
            type: 'string'
            index: true

      ExtendedModel = Record.getModel 'ExtendedModel'

      instance = new ExtendedModel
      instance.should.be.an.instanceof ExtendedModel
      ExtendedModel.should.have.property 'count'
      ExtendedModel.should.have.property 'get'
      ExtendedModel.count (error, count) ->
        count.should.eql 0
        ExtendedModel.sort field: 'name', (error, ids) ->
          should.not.exist error
          ids.length.should.be.equal 0
          done()


  it 'when it was extended by subclass', (done) ->

    Record.configure
      redis: require('redis').createClient()

    Record.model 'InheritedExtendedModel',
      properties:
        name:
          type: 'string'
        address:
          type: 'string'
      extends:
        dummy: ->
      methods:
        saveMyDay: ->

    InheritedExtendedModel = Record.getModel 'InheritedExtendedModel'
    instance = Record.factory 'InheritedExtendedModel'
    instance.should.be.an.instanceof InheritedExtendedModel
    InheritedExtendedModel.should.have.an.property 'count'
    InheritedExtendedModel.should.have.an.property 'dummy'
    instance.should.have.an.property 'saveMyDay'
    done()
