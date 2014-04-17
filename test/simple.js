// Generated by CoffeeScript 1.7.1
(function() {
  var ExtendedModel, InheritedExtendedModel, MyRecord, Record, redis, should;

  should = require('should');

  Record = require('../lib/record');

  MyRecord = require('./my_record');

  redis = require('redis').createClient();

  ExtendedModel = Record.model('ExtendedModel', {
    properties: {
      name: {
        type: 'string',
        index: true
      }
    },
    client: redis
  });

  InheritedExtendedModel = MyRecord.model('InheritedExtendedModel', {
    properties: {
      name: {
        type: 'string'
      },
      address: {
        type: 'string'
      }
    },
    client: redis
  });

  describe('Nohm model should be extended', function() {
    it('when it was extended by nohm-extend', function(done) {
      var instance;
      instance = new ExtendedModel;
      instance.should.be.an["instanceof"](Nohm);
      ExtendedModel.should.have.property('count');
      ExtendedModel.should.have.property('loadSome');
      return ExtendedModel.loadSome([1], function(err, instances) {
        err.should.eql('not found');
        return ExtendedModel.sort({
          field: 'name'
        }, function(err, ids) {
          ids.should.eql([]);
          return done();
        });
      });
    });
    return it('when it was extended by subclass', function(done) {
      var instance;
      instance = Nohm.factory('InheritedExtendedModel');
      instance.should.be.an["instanceof"](Nohm);
      InheritedExtendedModel.should.have.an.property('count');
      InheritedExtendedModel.should.have.an.property('dummy');
      instance.should.have.an.property('saveMyDay');
      return done();
    });
  });

}).call(this);
