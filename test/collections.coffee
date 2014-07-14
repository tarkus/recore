should = require 'should'
Redism = require 'redism'
Recore   = require '../lib'

describe 'Collections', ->

  before (done) ->
    Recore.configure
      redis: new Redism

    Recore.model 'ExtendedModel',
      properties:
        name:
          type: 'string'
          index: true
        date:
          type: 'timestamp'
          index: true

    done()

  it 'could be created', (done) ->
    ExtendedModel = Recore.getModel 'ExtendedModel'
    CollectionOne = ExtendedModel.collection('10000')
    CollectionAnother = ExtendedModel.collection('100000')
    CollectionCombo = ExtendedModel.collection('foo', 'bar')

    CollectionOne.modelName.should.equal "ExtendedModel:collection:10000"
    CollectionAnother.modelName.should.equal "ExtendedModel:collection:100000"
    CollectionCombo.modelName.should.equal "ExtendedModel:collection:foo+bar"

    CollectionOne.load 1, (error, props) ->
      Recore.collections.hasOwnProperty 'ExtendedModel:collection:10000'
      error.should.equal 'not found'

    CollectionOne.load 1, (error, props) ->
      Recore.collections.hasOwnProperty 'ExtendedModel:collection:10000'
      error.should.equal 'not found'

    CollectionCombo.load 1, (error, props) ->
      Recore.collections.hasOwnProperty 'ExtendedModel:collection:foo+bar'
      error.should.equal 'not found'
      done()

  it 'should behave like model', (done) ->
    ExtendedModel = Recore.getModel 'ExtendedModel'
    Collection = ExtendedModel.collection '100'
    CollectionCombo = ExtendedModel.collection 'foo', 'bar'

    sortOnWrongField = -> Collection.sort field: 'name'
    sortOnWrongField.should.throw "cannot sort on non-numeric fields with redism"

    sortOnWrongField = -> CollectionCombo.sort field: 'name'
    sortOnWrongField.should.throw "cannot sort on non-numeric fields with redism"

    done()
