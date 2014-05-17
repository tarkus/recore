{Nohm} = require "nohm"
assert = require 'assert'
hasher = require './hasher'
{EventEmitter} = require 'events'

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

  @getClient: -> Recore.client

  @getModel: (name) -> @getModels()[name]

  @getBaseModels: -> @base_models

  @getBaseModel: (name) -> @getBaseModels()[name]

  @configure: (options) ->
    assert options and options.redis, "Set redis client first"

    options.redis.connected = true
    @setClient options.redis
    @setPrefix options.prefix
    Recore.prefix = Nohm.prefix
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

      if typeof options is 'object' and options.field is 'id'
        options.limit ?= [0, 100]
        offset = options.limit[0]
        count = options.limit[1]
        direction = options.direction or 'DESC'

        for arg in arguments
          if typeof arg is 'function'
            callback = arg
            break

        callback ?= (err, ids) ->

        args = []

        return model.getClient().sort model.getIdsetsKey(), "LIMIT", \
          offset, count, direction, callback.bind model

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

    getUniqueIndexKey: (field, value) ->
      value = value.toLowerCase() if isNaN(value)
      "#{Recore.prefix.unique}#{@modelName}:#{field}:#{value}"

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

    create_index: (field) ->
      event = new EventEmitter

      model = @
      count = 0
      batch = 1
      batch_size = 100

      error_handler = (err) -> event.emit 'error' if err

      index = (field) ->
        prop = @properties[field]
        if prop.index
          if prop.__numericIndex
            key = model.getScoredIndexKey field
            model.getClient().zadd key, prop.value, @id, error_handler
          else
            key = model.getIndexKey field, prop.value
            model.getClient().sadd key, @id, error_handler
        if prop.unique
          key = model.getUniqueIndexKey field, prop.value
          model.getClient().setnx key, @id, error_handler

      run = ->
        event.emit 'checkpoint', count
        model.sort
          field: 'id'
          direction: 'ASC'
          limit: [(batch - 1) * batch_size, batch_size]
          , (err, ids) ->
            return event.emit 'halt', err if err
            return event.emit 'done', count if ids.length is 0
            batch_count = 0
            batch_total = ids.length
            batch++

            for id in ids
              do (id) ->
                model.load id, (err, props) ->
                  count++
                  batch_count++
                  if err
                    event.emit 'error'
                  else
                    if field
                      index.call @, field
                    else
                      index.call @, field for field, property of @properties

                  return event.emit 'next' if batch_count is batch_total

      model.count (err, count) ->
        return event.emit 'halt', err if err
        event.emit 'objects', count
        event.on 'next', run
        run()

      return event


    remove_index: (field) ->
      event = new EventEmitter
      event.emit 'halt', 'no field specified' unless field

      patterns =
        index: @getIndexKey field, '*'
        scoredindex: @getScoredIndexKey field, '*'
        uniques: @getUniqueIndexKey field, '*'

      count = 0
      total = 0
      batch_size = 100
      finished_clients = []

      idx = 0
      keys = Object.keys patterns
      clients = Object.keys Recore.getClient().clients

      scan = (client, pattern, cursor=0) ->
        event.emit 'checkpoint', count
        client.scan cursor, 'MATCH', pattern, 'COUNT', batch_size, (err, result) ->
          return event.emit 'halt', err if err

          [cursor, matches] = result

          return event.emit 'end', client if parseInt(cursor) is 0

          batch_count = matches.length
          if batch_count > 0
            total += batch_count
            event.emit 'objects', total
            args = keys.push (err, result) ->
              event.emit 'error', err if err
              count += batch_count
            client.del args

          return event.emit 'next', client, pattern, cursor

      event.on 'next', ->
        scan.apply @, arguments

      event.on 'end', (client) ->
        finished_clients.push client
        return event.emit 'finish' if finished_clients.length is clients.length

      event.on 'finish', ->
        return event.emit 'run'

      event.on 'run', ->
        return event.emit 'done', count if idx is keys.length
        key = keys[idx]
        pattern = patterns[key]
        finished_clients = []
        for dsn, client of Recore.getClient().clients
          do (client, pattern) -> scan client, pattern
        idx++

      # Life cycle for single pattern 
      #   run -> next cursor -> end cursor -> finish 
      event.emit 'run'

      return event

    remove_property: (field) ->
      event = new EventEmitter
      event.emit 'halt', 'no field specified' unless field

      pattern = @getHashKey field, '*'

      count = 0
      total = 0
      batch_size = 100
      finished_clients = []

      clients = Object.keys Recore.getClient().clients

      scan = (client, pattern, cursor=0) ->
        event.emit 'checkpoint', count
        client.scan cursor, 'MATCH', pattern, 'COUNT', batch_size, (err, result) ->
          return event.emit 'halt', err if err

          [cursor, matches] = result

          return event.emit 'end', client, pattern if parseInt(cursor) is 0

          batch_count = matches.length
          if batch_count > 0
            total += batch_count
            event.emit 'objects', total
            keys.forEach (key) ->
              client.hdel key, field, (err, result) ->
                event.emit 'error' if err
                count++
          return event.emit 'next', client, pattern, cursor

      event.on 'next', ->
        scan.apply @, arguments

      event.on 'end', (client, pattern) ->
        finished_clients.push client
        return event.emit 'done', count if finished_clients.length is clients.length

      event.on 'run', ->
        finished_clients = []
        for dsn, client of Recore.getClient().clients
          do (client, pattern) -> scan client, pattern

      remove_index_event = @remove_index(field)
      remove_index_event.on 'done', ->
        event.emit 'run'

      return event


  @_methods: null

module.exports = Recore
