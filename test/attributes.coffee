should = require 'should'
Recore = require '../lib'

describe 'Accessible attributes', ->

  it 'should be able to be defined in attr_accessible', (done) ->

    Recore.configure
      redis: require('redis').createClient()

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

    should(ins.attr()).eql ins.attributes(), 'Alias attr'
    should(ins.attrs()).eql ins.attributes(), 'Alias attrs'

    done()
