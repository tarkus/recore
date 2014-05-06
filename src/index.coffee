{Nohm} = require "nohm"
assert = require 'assert'
hasher = require './hasher'

schemas = {}

extend = (dest, objs...) ->
  for obj in objs
    dest[k] = v for k, v of obj
  dest

recycle = ->
  ids = Object.keys Recore.collections
  if ids.length > COLLECTION_RECYCLE_TARGET
    ids = ids.slice(0, COLLECTION_RECYCLE_QUATITY)
    ids.forEach (name) -> return delete Recore.collections[name]
  return setTimeout recycle, COLLECTION_RECYCLE_INTERVAL

COLLECTION_TTL = 300000 # View idle for 5 min = inactive
COLLECTION_RECYCLE_INTERVAL = 600000 # Do house work every 10 min
COLLECTION_RECYCLE_QUATITY = 1000
COLLECTION_RECYCLE_TARGET = 10000

setTimeout recycle, COLLECTION_RECYCLE_INTERVAL

class Recore extends Nohm

  @collections: {}

  @base_models: {}

  @getModel: (name) -> @getModels()[name]

  @getBaseModels: -> @base_models

  @getBaseModel: (name) -> @getBaseModels()[name]

  @configure: (options) ->
    assert options and options.redis, "Set redis client first"

    options.redis.connected = true
    @setClient options.redis
    @setPrefix options.prefix
    Recore.client = Nohm.client
    
    if options.models
      if options.models.charAt(0) isnt "/"
        options.models = require('path').dirname(module.parent.filename) + "/" + options.models
      for filename in require('fs').readdirSync(options.models)
        require options.models + "/" + filename

    return Recore

  @model: (name, options, temp) ->
    schemas[name] = options
    options.methods ?= {}
    options.extends ?= {}

    options.methods = extend options.methods, @_methods

    model = Nohm.model(name, options, temp)
    model = extend model, @_extends, options.extends
    model.modelName = name

    @base_models[name] = model

    # Collections!
    model.collectionDefinition = options.properties.collections or null

    if model.collectionDefinition
      if Array.isArray model.collectionDefinition
        collections = model.collectionDefinition
      else if typeof model.collectionDefinition is 'object'
        collections = Object.keys model.collectionDefinition
      else
        throw new Error "wrong type of collection definition"

      collections.forEach (key) -> model.collection key

    model.__findAndLoad = model.findAndLoad
    model.findAndLoad = (searches, callback) ->
      if typeof searches is 'function'
        callback = searches
        searches = {}
      model.__findAndLoad.call model, searches, callback

    model.__find = model.find
    model.find = (searches, callback) ->
      if @getClient().shardable \
        and searches and typeof(searches) isnt 'function' \
        and Object.keys(searches).length > 1
          return throw new Error "cannot search more one criteria with redism"
      model.__find.apply @, arguments

    model.__sort = model.sort
    model.sort = (options, ids) ->
      ins = new model
      if @getClient().shardable
        field_type = ins.properties[options.field].type
        scored = Recore.indexNumberTypes.indexOf(field_type) != -1
        return throw new Error "cannot sort on non-numeric fields with redism" unless scored
        return throw new Error "cannot sort on subset with redism" unless Array.isArray ids if Array.isArray ids

      model.__sort.apply @, arguments

    return model

  @_methods: {}

  @_extends:

    collection: (key) ->
      name = "#{@modelName}:collection:#{key}"
      collection = Recore.collections[name]
      unless collection
        model = @
        collection = Recore.model name, schemas[model.modelName]
        collection.modelName = name
        collection::modelName = name
        Recore.collections[name] = collection
      collection

    getClient: -> Recore::getClient()

    getIdsKey: -> "#{Recore.prefix.ids}#{@modelName}"

    getIdsetsKey: -> "#{Recore.prefix.idsets}#{@modelName}"

    getHashKey: (id) -> "#{Recore.prefix.hash}#{@modelName}:#{id}"

    getScoredIndexKey: (field) -> "#{Recore.prefix.scoredindex}#{@modelName}:#{field}"

    getIndexKey: (field, value) -> "#{Recore.prefix.index}#{@modelName}:#{field}:#{value}"

    getUniqueIndexKey: (field, value) -> "#{Recore.prefix.unique}#{@modelName}:#{field}:#{value}"

    get: (criteria, callback) ->
      @findAndLoad criteria, (err, objs) ->
        return callback(err) if err
        if objs.length is 1
          callback.call(objs[0], null, objs[0].allProperties())
        else
          callback.call(null, objs)

    find_or_create: (criteria, callback) ->
      model = @
      @find criteria, (err, ids) =>
        if err is 'not found' or ids.length is 0
          new_obj = new model
          new_obj.prop criteria
          return callback null, new_obj
        return callback err if err
        return callback "more than one" if ids.length > 1
        @load ids.pop(), (err, props) ->
          return callback err if err
          return callback null, @

    ids: (ids, callback) ->
      return callback(null, []) if ids.length is 0
      rows = []
      count = 0
      total = ids.length
      for id in ids
        @load parseInt(id), (err, props) ->
          return callback(err) if err
          rows.push @allProperties()
          count++
          callback(null, rows) if count is total

    count: (criteria, callback) ->
      if typeof criteria is 'function'
        callback = criteria
        criteria = null
        m = new this
        return @getClient().scard Recore.prefix.idsets + m.modelName, (err, result) ->
          return callback err if err
          return callback null, result

      @find criteria, (err, ids) ->
        return callback err if err
        return callback null, ids.length

    index: (property, callback) ->
      if typeof property is "function"
        callback = property
        property = null

      model = @
      multi = @getClient().multi()
      affected_rows = 0
      old_unique = []
      new_unique = []
      @find (err, ids) =>
        return callback.call model, err, affected_rows if err or ids.length < 1
        ids.forEach (id, idx) =>
          @load id, (err, props) ->
            console.log id, @errors if err
            set_update = (prop) =>
              if @properties[prop].unique
                propLower = if @properties[prop].type is 'string' \
                  then @properties[prop].__oldValue.toLowerCase() \
                  else @properties[prop].__oldValue
                multi.setnx "#{Recore.prefix.unique}#{@modelName}:#{prop}:#{@properties[prop].value}", id
              else
                @properties[prop].__updated = true

            if property
              set_update(property)
            else
              for p, def of @properties when def.index or def.unique
                set_update(p)

            @save (err) ->
              console.log "Indexed #{@modelName} on '#{property or 'all indexed properties'}' for row id #{@id}"
              affected_rows += 1
              if idx is ids.length - 1
                multi.exec()
                callback.call model, err, affected_rows

    deindex: (properties, callback) ->
      model = @
      multi = @getClient().multi()
      deletes = []
      if typeof properties is 'function'
        callback = properties
        properties = null
      properties = [properties] if typeof properties is 'string'
      unless properties
        ins = new model
        properties = []
        for p, def of ins.properties when def.index or def.unique
          properties.push p

      properties.forEach (p, idx) =>
        Recore.client.keys "#{Recore.prefix.unique}#{@modelName}:#{p}:*", (err, unique_keys) =>
          deletes = unique_keys
          Recore.client.keys "#{Recore.prefix.index}#{@modelName}:#{p}:*", (err, index_keys) =>
            deletes = deletes.concat index_keys
            Recore.client.keys "#{Recore.prefix.scoredindex}#{@modelName}:#{p}:*", (err, scoredindex_keys) =>
              deletes = deletes.concat scoredindex_keys

              if idx is properties.length - 1
                multi.del deletes if deletes.length > 0
                multi.exec (err, results) =>
                  console.log "Deleted #{deletes.length} related keys for '#{properties.join(', ')}' of #{@modelName}"
                  return callback.call model, err, deletes.length


    clean: (callback) ->
      model = new @
      multi = Recore.client.multi()
      deletes = []
      affected_rows = 0
      undefined_properties = []
      @find (err, ids) =>
        return callback.call @, err, affected_rows if err or ids.length < 1
        ids.forEach (id, idx) =>
          @getClient().hgetall @getHashKey(id), (err, values) =>
            keys = if values then Object.keys(values) else []
            err = 'not found' unless Array.isArray(keys) and keys.length > 0 and not err

            if err
              Recore.logError "loading a hash produced an error: #{err}"
              return callback?.call @, err

            # Delete unused properties
            for p of values
              is_enumerable = values.hasOwnProperty(p)
              is_meta = p is '__meta_version'
              is_property = model.properties.hasOwnProperty(p)
              if not is_meta and not model.properties.hasOwnProperty(p)
                affected_rows += 1
                if undefined_properties.indexOf(p) is -1
                  Recore.logError "Undefined property '#{p}' found, will be deleted"
                  undefined_properties.push p
                multi.hdel @getHashKey(id), p

            # Delete unused index keys
            if idx is ids.length - 1
              return callback.call model, err, affected_rows unless undefined_properties.length > 0
              multi.exec (err, results) ->
                console.log "Cleaned up undefined properties #{undefined_properties.join(', ')}"
              @deindex undefined_properties, callback


  @_methods: null

module.exports = Recore
