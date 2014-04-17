should = require 'should'
Redism = require 'redism'
Record = require '../lib/record'

describe 'Nohm model on redism should be extended', ->

  before (done) ->
    Record.configure
      redis: new Redism
      connect: ->
        Record.model 'ExtendedModel',
          properties:
            name:
              type: 'string'
              index: true
            date:
              type: 'timestamp'
              index: true

        done()

  it 'when it was extended by record', (done) ->
      ExtendedModel = Record.getModel 'ExtendedModel'
      instance = new ExtendedModel
      instance.should.be.an.instanceof ExtendedModel
      ExtendedModel.should.have.property 'count'
      ExtendedModel.should.have.property 'get'
      ExtendedModel.count (error, count) ->
        count.should.eql 0
        done()


  it 'sort is restricted', (done) ->
    ExtendedModel = Record.getModel 'ExtendedModel'
    sortOnWrongField = -> ExtendedModel.sort field: 'name'
    sortOnWrongField.should.throw "cannot sort on non-numeric fields with redism"

    ExtendedModel.sort field: 'date', (error, ids) ->
      should.not.exists error
      ids.length.should.equal 0
      done()

  it 'find only work on single criteria', (done) ->
    ExtendedModel = Record.getModel 'ExtendedModel'
    findByOneCriteria = -> ExtendedModel.find name: 'foo', -> 'pass'
    findByOneCriteria.should.not.throw()

    findByMultiCriteria = -> ExtendedModel.find {name: 'foo', date: 'bar'}, -> 'pass'
    findByMultiCriteria.should.throw()
    done()
