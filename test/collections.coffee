should = require 'should'
Redism = require 'redism'
Record = require '../lib'

describe 'Collections', ->

  before (done) ->
    Record.configure
      redis: new Redism

    Record.model 'ExtendedModel',
      properties:
        name:
          type: 'string'
          index: true
        date:
          type: 'timestamp'
          index: true

    done()

  it 'could be created', (done) ->
    ExtendedModel = Record.getModel 'ExtendedModel'
    CollectionOne = ExtendedModel.collection('10000')
    CollectionAnother = ExtendedModel.collection('100000')

    CollectionOne.modelName.should.equal "ExtendedModel:collection:10000"
    CollectionAnother.modelName.should.equal "ExtendedModel:collection:100000"

    CollectionOne.load 1, (error, props) ->
      Record.collections.hasOwnProperty 'ExtendedModel:collection:10000'
      error.should.equal 'not found'
      done()

  it 'should behave like model', (done) ->
    ExtendedModel = Record.getModel 'ExtendedModel'
    Collection = ExtendedModel.collection '100'

    sortOnWrongField = -> Collection.sort field: 'name'
    sortOnWrongField.should.throw "cannot sort on non-numeric fields with redism"

    done()
