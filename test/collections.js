// Generated by CoffeeScript 1.7.1
(function() {
  var Record, Redism, should;

  should = require('should');

  Redism = require('redism');

  Record = require('../lib/record');

  describe('Collections', function() {
    before(function(done) {
      return Record.configure({
        redis: new Redism,
        connect: function() {
          Record.model('ExtendedModel', {
            properties: {
              name: {
                type: 'string',
                index: true
              },
              date: {
                type: 'timestamp',
                index: true
              }
            }
          });
          return done();
        }
      });
    });
    it('could be created', function(done) {
      var ExtendedModel;
      ExtendedModel = Record.getModel('ExtendedModel');
      return ExtendedModel.collection('10000').load(1, function(error, props) {
        Record.collections.hasOwnProperty('ExtendedModel:collection:10000');
        error.should.equal('not found');
        return done();
      });
    });
    return it('should behave like model', function(done) {
      var Collection, ExtendedModel, sortOnWrongField;
      ExtendedModel = Record.getModel('ExtendedModel');
      Collection = ExtendedModel.collection('100');
      sortOnWrongField = function() {
        return Collection.sort({
          field: 'name'
        });
      };
      sortOnWrongField.should["throw"]("cannot sort on non-numeric fields with redism");
      return done();
    });
  });

}).call(this);