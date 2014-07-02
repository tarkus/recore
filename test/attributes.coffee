should = require 'should'
Recore = require '../lib'

Recore.configure
  redis: require('redis').createClient()

describe 'Accessible attributes', ->

  it 'should be able to be defined in attr_accessible', (done) ->

    Recore.model 'TestModel',
      attr_accessible: [ 'accessible_foo', 'accessible_bar' ]
      properties:
        accessible_foo:
          type: 'string'
          index: true
        accessible_bar:
          type: 'string'
          index: true
        unaccessible_foo:
          type: 'string'
          index: true
        unaccessible_bar:
          type: 'string'
          index: true

    TestModel = Recore.getModel 'TestModel'
    ins = new TestModel
    ins.prop
      accessible_foo: 'foo'
      accessible_bar: 'bar'

    ins.attributes().accessible_foo.should.equal 'foo'
    ins.attributes().accessible_bar.should.equal 'bar'

    should.not.exist ins.attributes().unaccessible_foo
    should.not.exist ins.attributes().unaccessible_bar

    done()

  it 'methods can be overrided', (done) ->

    Recore.model 'TestModelOverride',
      attr_accessible: [ 'accessible_foo', 'accessible_bar' ]
      properties:
        accessible_foo:
          type: 'string'
          index: true
        accessible_bar:
          type: 'string'
          index: true
        unaccessible_foo:
          type: 'string'
          index: true
        unaccessible_bar:
          type: 'string'
          index: true

      methods:

        attributes: ->
          attrs = @_super_attributes()
          attrs.unaccessible_foo = @prop 'unaccessible_foo'
          attrs

    TestModelOverride = Recore.getModel 'TestModelOverride'
    ins = new TestModelOverride
    ins.prop
      accessible_foo: 'foo'
      accessible_bar: 'bar'

    should(ins.attr()).eql ins.attributes(), 'Alias attr'
    should(ins.attrs()).eql ins.attributes(), 'Alias attrs'

    should.exist ins.attributes().unaccessible_foo
    should.not.exist ins.attributes().unaccessible_bar

    done()
