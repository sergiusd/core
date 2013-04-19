baseUrl = '/'

require.config

  baseUrl: baseUrl

  urlArgs: "uid=" + (new Date()).getTime()

  paths:
    'postal':           'vendor/postal/postal_lite'
    'monologue':        'vendor/postal/monologue'
    'dustjs-linkedin':  'vendor/dustjs/dustjs-full'
    'dustjs-helpers':   'vendor/dustjs/dustjs-helpers'
    'jquery':           'vendor/jquery/jquery'
    'jquery.ui':        'vendor/jquery/ui/jquery-ui'
    'jquery.cookie':    'vendor/jquery/plugins/jquery.cookie'
    'jquery.color':     'vendor/jquery/plugins/jquery.color'
    'jquery.scrollTo':  'vendor/jquery/plugins/jquery.scrollTo'
    'jquery.dotdotdot': 'vendor/jquery/plugins/jquery.dotdotdot'
    'jquery.jeditable': 'vendor/jquery/plugins/jquery.jeditable'
    'jquery.removeClass': 'vendor/jquery/plugins/jquery.removeClass'
    'curly':            'vendor/curly/browser'
    'underscore':       'vendor/underscore/underscore'
    'requirejs':        'vendor/requirejs/require'
    'the-box':          'vendor/the-box/app'
    'moment':           'vendor/moment/moment'
    'moment-ru':        'vendor/moment/lang/ru'
    'sockjs':           'vendor/sockjs/sockjs'
    'ecomet':           'bundles/megaplan/front/common/utils/Ecomet'

  shim:
    'dustjs-linkedin':
      exports: 'dust'
    'dustjs-helpers':
      deps: ['dustjs-linkedin']
      exports: 'dust'
    'underscore':
      exports: '_'


define [
  'jquery'
  'bundles/cord/core/configPaths'
], ($, configPaths) ->

  require.config configPaths
  require [
    'cord!/cord/core/appManager'
    'cord!WidgetRepo'
    'cord!ServiceContainer'
    'cord!css/browserManager'
  ], (clientSideRouter, WidgetRepo, ServiceContainer, cssManager) ->

    serviceContainer = new ServiceContainer()

    ###
      Конфиги
    ###

    serviceContainer.def 'config', ->
      api:
        protocol: 'http'
        host: window.location.host
        urlPrefix: 'XDR/http://megaplan.megaplan.ru/api/v2/'
        getUserPasswordCallback: (callback) ->
          window.location.href = '/user/login/?back=' + window.location.pathname
      ecomet:
        host: 'megaplan.megaplan.ru'
        authUri: '/SdfCommon/EcometOauth/auth'
      oauth2:
        clientId: 'ce8fcad010ef4d10a337574645d69ac8'
        secretKey: '2168c151f895448e911243f5c6d6cdc6'
        endpoints:
          accessToken: 'http://' + window.location.host + '/XDR/http://megaplan.megaplan.ru/oauth/access_token'

    ###
      Это надо перенести в более кошерное место
    ###

    #Global errors handling
    requirejs.onError = (error)->
      requirejs ['postal'], (postal)->
        message = 'Ой! Кажется, нет связи, подождите, может восстановится.'
        postal.publish 'notify.addMessage', {link:'', message: message, details: error.toString(), error:true, timeOut: 50000 }

    serviceContainer.def 'request', (get, done) ->
      requirejs ['cord!/cord/core/request/BrowserRequest'], (Request) ->
        done null, new Request serviceContainer

    serviceContainer.def 'cookie', (get, done) ->
      requirejs ['cord!/cord/core/cookie/BrowserCookie'], (Cookie) ->
        done null, new Cookie serviceContainer

    serviceContainer.def 'oauth2', ['config'], (get, done) ->
      requirejs ['cord!/cord/core/OAuth2'], (OAuth2) ->
        done null, new OAuth2 serviceContainer, get('config').oauth2

    serviceContainer.def 'api', ['config'], (get, done) ->
      requirejs ['cord!/cord/core/Api'], (Api) ->
        done null, new Api serviceContainer, get('config').api

    serviceContainer.def 'user', ['api'], (get, done) ->
      get('api').get 'employee/current/?_extra=user.id', (response) =>
        done null, response

    serviceContainer.def 'discussRepo', (get, done) ->
      requirejs ['cord-m!/megaplan/front/talks//DiscussRepo'], (DiscussRepo) ->
        done null, new DiscussRepo(serviceContainer)

    serviceContainer.def 'discussFilterRepo', (get, done) ->
      requirejs ['cord-m!/megaplan/front/talks//DiscussFilterRepo'], (DiscussFilterRepo) ->
        done null, new DiscussFilterRepo(serviceContainer)

    serviceContainer.def 'taskRepo', (get, done) ->
      requirejs ['cord-m!/megaplan/front/tasks//TaskRepo'], (TaskRepo) ->
        done null, new TaskRepo(serviceContainer)

    serviceContainer.def 'taskFilterRepo', (get, done) ->
      requirejs ['cord-m!/megaplan/front/tasks//TaskFilterRepo'], (TaskFilterRepo) ->
        done null, new TaskFilterRepo(serviceContainer)

    serviceContainer.def 'userStats', (get, done) ->
      requirejs ['cord!/megaplan/front/common/utils/UserStat'], (UserStat) ->
        done null, new UserStat(serviceContainer)

    serviceContainer.def 'ecomet', ['cookie', 'config'], (get, done) ->
      requirejs ['ecomet'], (Ecomet) ->
        done null, new Ecomet(get('cookie').get('accessToken'), get('config').ecomet)

    ###
    ###

    widgetRepo = new WidgetRepo

    serviceContainer.set 'widgetRepo', widgetRepo
    widgetRepo.setServiceContainer serviceContainer

    clientSideRouter.setWidgetRepo widgetRepo
    clientSideRouter.process()
    $ ->
      cssManager.registerLoadedCssFiles()
      cordcorewidgetinitializerbrowser? widgetRepo
