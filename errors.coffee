define ->
  ###
  Custom exception classes used in the framework's core
  ###

  WidgetDropped: class WidgetDropped extends Error
    constructor: (@message) ->
      @name = 'WidgetDropped'
      Error.call(this, @message)
      Error.captureStackTrace?(this, arguments.callee)


  WidgetSentenced: class WidgetSentenced extends Error
    constructor: (@message) ->
      @name = 'WidgetSentenced'
      Error.call(this, @message)
      Error.captureStackTrace?(this, arguments.callee)


  WidgetParamsRace: class WidgetParamsRace extends Error
    constructor: (@message) ->
      @name = 'WidgetParamsRace'
      Error.call(this, @message)
      Error.captureStackTrace?(this, arguments.callee)
