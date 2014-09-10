define [
  'cord!Widget'
  'cord!utils/Future'
  'underscore'
], (Widget, Future, _) ->

  calculateDeepHighlight = (info, timers) ->
    ###
    Recursively walks through tree of `timers` and constructs related tree with highlighting info
     according to the given timer ids in `info`
    @param Object info dependency timer ids
    @param Array[Object] timers
    @return Object
    ###
    result =
      bubbleType: 'none'
      timers: {}
    for timer in timers
      hInfo = type: 'none'
      if timer.id == info.selectedTimerId
        hInfo.type = 'selected'
      else if timer.id in info.depTimerIds
        hInfo.type = 'dep'

      if timer.children?
        childRes = calculateDeepHighlight(info, timer.children)
        hInfo.children = childRes.timers
        hInfo.type = childRes.bubbleType if hInfo.type == 'none'
        hInfo.type = 'selected-dep-parent' if hInfo.type == 'selected' and childRes.bubbleType == 'dep-parent'
        hInfo.type = 'dep-dep-parent' if hInfo.type == 'dep' and childRes.bubbleType == 'dep-parent'

      result.timers[timer.id] = hInfo

      if hInfo.type in ['dep', 'dep-parent', 'dep-dep-parent']
        result.bubbleType = 'dep-parent'
      else if hInfo.type in ['selected', 'selected-dep-parent'] and result.bubbleType != 'dep-parent'
        result.bubbleType = 'selected-parent'
      else if result.bubbleType == 'none'
        result.bubbleType = hInfo.type

    result


  class Profiler extends Widget
    ###
    Controller widget for the profiler debug panel
    @browser-only
    ###

    behaviourClass: false

    @initialCtx:
      timers: []

    @params:
      serverUid: 'loadServerProfilingData'

    @childEvents:
      'panel actions.highlight-wait-deps': 'highlightWaitDeps'


    highlightWaitDeps: (highlightInfo) ->
      @ctx.set('highlightInfo', calculateDeepHighlight(highlightInfo, @ctx.timers).timers)


    loadServerProfilingData: (serverUid) ->
      ###
      @browser-only
      ###
      Future.require('jquery').then ($) =>
        $.getJSON("/assets/p/#{serverUid}.json").then (data) =>
          newTimers = _.clone(@ctx.timers)
          @_calculateDerivativeMetrics(data)
          newTimers.unshift(data)
          @ctx.set timers: newTimers


    _calculateDerivativeMetrics: (timerData) ->
      ###
      Calculates some derivative metrics from the very minimum of primary metrics of timers came from server
      Mutates incoming timerData struct
      @param Object timerData
      ###
      pureExecTime = 0
      max = timerData.ownFinishTime = timerData.startTime + timerData.syncTime + (timerData.asyncTime ? 0)
      if timerData.children
        for child in timerData.children
          @_calculateDerivativeMetrics(child)
          max = child.finishTime if child.finishTime > max
          pureExecTime += child.pureExecTime
      timerData.finishTime = max
      timerData.totalTime = timerData.finishTime - timerData.startTime # total duration until finish including children
      timerData.pureExecTime = pureExecTime + timerData.ownAsyncTime   # total execution time of chunks in event-loop
                                                                       # including children
      undefined