define [
  'cord!AppConfigLoader'
  'cord!cache/localStorage'
  'cord!Console'
  'cord!css/browserManager'
  'cord!router/clientSideRouter'
  'cord!PageTransition'
  'cord!ServiceContainer'
  'cord!WidgetRepo'
  'jquery'
], (AppConfigLoader, localStorage, _console, cssManager,
    clientSideRouter, PageTransition, ServiceContainer, WidgetRepo, $) ->

  class ClientFallback

    constructor: (@router) ->

    fallback: (newWidgetPath, params) ->
      @router.widgetRepo.transitPage(newWidgetPath, params, new PageTransition(@router.currentPath, @router.currentPath))


  -> # browserInit() function
    ###
    Initializes cordsjs core on browser-side
    ###
    serviceContainer = new ServiceContainer
    serviceContainer.set 'container', serviceContainer

    window._console = _console

    configInitFuture = AppConfigLoader.ready().map (appConfig) ->
      clientSideRouter.addRoutes(appConfig.routes)
      clientSideRouter.addFallbackRoutes(appConfig.fallbackRoutes)
      for serviceName, info of appConfig.services
        do (info) ->
          serviceContainer.def serviceName, info.deps, (get, done) ->
            info.factory.call(serviceContainer, get, done)

      ###
        Конфиги
      ###

      serviceContainer.def 'config', ->
        config = global.config
        config.api.authenticateUserCallback = ->
          backPath = window.location.pathname
          if not (backPath.indexOf('user/login') >= 0 or backPath.indexOf('user/logout') >= 0)
            clientSideRouter.navigate '/user/login/?back=' + window.location.pathname
          true
        config

    ###
      Это надо перенести в более кошерное место
    ###

    #Global errors handling
    requirejs.onError = (error) ->
      if global.config.debug.require
        throw error
      else
        _console.error 'Error from requirejs: ', error.toString(), 'Error: ', error

    # Clear localStorage in case of changing collections' release number
    localVersion = localStorage.getItem 'collectionsVersion'
    currentVersion = window.global.config.static.collection
    if currentVersion != localVersion
      localStorage.clear()
      localStorage.setItem 'collectionsVersion', currentVersion

    widgetRepo = new WidgetRepo

    fallback = new ClientFallback(clientSideRouter)

    serviceContainer.set 'fallback', fallback
    serviceContainer.set 'router', clientSideRouter

    serviceContainer.set('widgetRepo', widgetRepo)
    widgetRepo.setServiceContainer(serviceContainer)

    clientSideRouter.setWidgetRepo(widgetRepo)
    $ ->
      cssManager.registerLoadedCssFiles()
      configInitFuture.done -> cordcorewidgetinitializerbrowser?(widgetRepo)