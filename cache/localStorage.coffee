define [
  'cord!utils/Future'
  'cord!utils/sha1'
], (Future, sha1) ->

  class LocalStorage

    storage: window.localStorage


    saveCollectionInfo: (repoName, collectionName, ttl, info) ->
      ###
      Saves only collections meta-information
      ###
      key = "cl:#{ repoName }:#{ sha1(collectionName) }"
      if ttl?
        @_registerTtl(key + ':info', ttl)
        @_registerTtl(key, ttl)
      @_set(key + ':info', info)
      

    saveCollection: (repoName, collectionName, modelIds) ->
      ###
      Saves list of model ids for the collection.
      ###
      @_set("cl:#{ repoName }:#{ sha1(collectionName) }", modelIds)
      

    invalidateCollection: (repoName, collectionName) ->
      ###
      Removes collection from cache
      ###
      key = "cl:#{ repoName }:#{ sha1(collectionName) }"
      @_removeItem key
      @_removeItem(key + ':info')
      

    invalidateAllCollectionsWithField: (repoName, fieldName) ->
      ###
      Clear cache for collections of particular repo, which contains the fieldName
      ###
      @_invalidateAllCollectionsWithField repoName, fieldName

    setItem: (key, value) ->
      ###
      Set wrapper
      ###
      @storage.setItem(key, value)


    getCollectionInfo: (repoName, collectionName) ->
      ###
      Returns meta-information of the collection, previously saved in the local storage.
      ###
      @_get("cl:#{ repoName }:#{ sha1(collectionName) }:info")


    getCollection: (repoName, collectionName) ->
      ###
      Returns list of model ids of the collection, previously saved in the local storage.
      ###
      @_get("cl:#{ repoName }:#{ sha1(collectionName) }")


    getItem: (key) ->
      ###
      Get wrapper
      ###
      @storage.getItem(key)


    removeItem: (key) ->
      @storage.removeItem(key)


    clear: ->
      ###
      Clear local storage
      ###
      @storage.clear()
      
      
    _removeItem: (key) ->
      result = Future.single('localStorage::_remove')
      try
        @storage.removeItem key
        result.resolve()
      catch e
          result.reject(e)
      result


    _set: (key, value) ->
      ###
      Key-value set proxy for the local storage with serialization and garbage collection fired when not enough space.
      Garbage collection is base on the TTL params, passed when saving values.
      ###
      result = Future.single('localStorage::_set')
      strValue = JSON.stringify(value)
      try
        @storage.setItem(key, strValue)
        result.resolve()
      catch e
        if e.code == DOMException.QUOTA_EXCEEDED_ERR or e.name.toLowerCase().indexOf('quota') != -1
          @_gc(strValue.length)
          try
            @storage.setItem(key, strValue)
            result.resolve()
          catch e
            _console.error "localStorage::_set(#{ key }) failed!", value, e
            result.reject(e)
        else
          result.reject(e)
      result


    _get: (key) ->
      ###
      Future-powered proxy key-value get method.
      ###
      value = @storage.getItem(key)
      if value?
        Future.resolved(JSON.parse(value))
      else
        Future.rejected("Key '#{ key }' doesn't exists in the local storage!")


    _registerTtl: (key, ttl) ->
      ###
      Saves TTL for the given key to be able to make right decisions during GC
      ###
      ttlInfo = JSON.parse(@storage.getItem('models:ttl-info'))
      ttlInfo ?= {}

      ttlInfo[key] = (new Date).getTime() + ttl

      @_set('models:ttl-info', ttlInfo)


    _gc: (needLength) ->
      ###
      Garbage collector.
      If needLength argument is given, than it tries to free just enought space, if not - all expired items are removed.
      @param (optional) needLength amount of memory needed
      ###
      ttlInfo = JSON.parse(@storage.getItem('models:ttl-info'))
      if needLength
        needLength = parseInt(needLength) * 2
      else
        needLength = 0
      orderedTtlInfo = []
      for k, v of ttlInfo
        orderedTtlInfo.push [k, v]
      orderedTtlInfo = _.sortBy orderedTtlInfo, (x) -> x[1]

      if needLength
        while needLength > 0 and orderedTtlInfo.length
          item = orderedTtlInfo.shift()
          val = @storage.getItem(item[0])
          if val?
            needLength -= val.length
            @storage.removeItem(item[0])
          delete ttlInfo[item[0]]
      else
        currentTime = (new Date).getTime()
        for item in orderedTtlInfo
          if item[1] < currentTime
            @storage.removeItem(item[0])
            delete ttlInfo[item[0]]
          else
            break

      @_set('models:ttl-info', ttlInfo)


    _invalidateAllCollectionsWithField: (repoName, fieldName) ->
      result = Future.single('localStorage::_invalidateAllCollectionsWithField')
      for k,v of @storage
        if k.slice(-5) == ':info' && k.indexOf(repoName) >= 0 && v
          if !fieldName
            @storage.removeItem k
            @storage.removeItem(k.slice(0, k.length - 5))
          else
            infoObject = JSON.parse(v)
            if !infoObject.fields || (fieldName in infoObject.fields)
                @storage.removeItem k
                @storage.removeItem(k.slice(0, k.length - 5))
          
      result.resolve()
      result
          

    _invalidateAllCollections: (repoName) ->
      result = Future.single('localStorage::_invalidateAllCollectionsWithField')
      for k,v of @storage
        if k.indexOf(repoName) >= 0 && v
          @storage.removeItem k
          @storage.removeItem(k.slice(0, k.length - 5))
      result.resolve()
      result


  new LocalStorage
