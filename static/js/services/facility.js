var _ = require('underscore');

(function () {

  'use strict';

  var inboxServices = angular.module('inboxServices');

  // Copied Facility into a legacy copy so we can move things piecemeal.
  // If we ever get to a wonderful state where no one uses this DELETEEE IT
  inboxServices.factory('LegacyFacility', ['DbView', 'Cache', 'CONTACT_TYPES',
    function(DbView, Cache, CONTACT_TYPES) {

      var cache = Cache({
        get: function(callback) {
          DbView('facilities', { params: { include_docs: true } })
            .then(function(data) {
              callback(null, data.results);
            })
            .catch(callback);
        },
        invalidate: function(doc) {
          return _.contains(CONTACT_TYPES, doc.type);
        }
      });

      return function(options, callback) {
        if (!callback) {
          callback = options;
          options = {};
        }
        cache(function(err, res) {
          if (err) {
            return callback(err);
          }
          if (options.types) {
            return callback(null, _.filter(res, function(doc) {
              return options.types.indexOf(doc.type) !== -1;
            }));
          }
          callback(null, res);
        });
      };
    }
  ]);

  inboxServices.factory('Facility', ['DbView', 'Cache', 'PLACE_TYPES',
    function(DbView, Cache, PLACE_TYPES) {

      var cache = Cache({
        get: function(callback) {
          DbView('facilities', { params: { include_docs: true } })
            .then(function(data) {
              callback(null, data.results);
            })
            .catch(callback);
        },
        invalidate: function(doc) {
          return _.contains(PLACE_TYPES, doc.type);
        }
      });

      return function(options, callback) {

        if (!callback) {
          callback = options;
          options = {};
        }

        if (!options.types ||
            options.types.indexOf('person') !== -1) {

          console.warn('A call to facility with the expectation of having ' +
                       'person data', new Error());
        }

        cache(function(err, res) {
          if (err) {
            return callback(err);
          }
          if (options.types) {
            return callback(null, _.filter(res, function(doc) {
              return options.types.indexOf(doc.type) !== -1;
            }));
          }
          callback(null, res);
        });
      };
    }
  ]);

  var descendant = function(id, parent) {
    if (!parent) {
      return false;
    }
    if (parent._id === id) {
      return true;
    }
    return descendant(id, parent.parent);
  };

  inboxServices.factory('Contact', ['LegacyFacility', 'UserDistrict',
    function(LegacyFacility, UserDistrict) {
      return function(callback) {
        UserDistrict(function(err, district) {
          if (err) {
            return callback(err);
          }
          var options = {
            district: district,
            types: [ 'person', 'health_center' ],
            targetScope: 'root'
          };
          LegacyFacility(options, function(err, res) {
            if (err) {
              return callback(err);
            }
            var contacts = [];
            _.each(res, function(contact) {
              if (contact.type === 'person' && contact.phone) {
                contacts.push(contact);
              } else if (contact.type === 'health_center') {
                contacts.push(_.extend({
                  everyoneAt: true,
                  descendants: _.filter(res, function(child) {
                    return descendant(contact._id, child.parent);
                  })
                }, contact));
              }
            });
            callback(null, contacts);
          });
        });
      };
    }
  ]);

  inboxServices.factory('District', ['DbView',
    function(DbView) {
      return function(callback) {
        var options = { params: { key: ['district_hospital'], include_docs: true } };
        DbView('facilities', options)
          .then(function(data) {
            callback(null, data.results);
          })
          .catch(callback);
      };
    }
  ]);

  inboxServices.factory('ChildFacility', ['DbView',
    function(DbView) {

      return function(parent, callback) {
        var params = {
          group: true
        };
        if (parent.type === 'district_hospital') {
          // filter on district
          params.startkey = [ parent._id ];
          params.endkey = [ parent._id, {} ];
        } else if (parent.type === 'health_center') {
          // filter on health center
          params.startkey = [ parent.parent._id, parent._id ];
          params.endkey = [ parent.parent._id, parent._id, {} ];
        } else {
          return callback('Doc not currently supported.');
        }
        DbView('total_clinics_by_facility', { params: params })
          .then(function(data) {
            callback(null, data.results);
          })
          .catch(callback);
      };

    }
  ]);

}());
