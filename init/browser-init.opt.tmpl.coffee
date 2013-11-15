###
Template for the browser initialization script generated by the optimizer.
COMPUTED-REQUIREJS-CONFIG should be replaced by the actual collected configuration object
###

require.config(COMPUTED_REQUIREJS_CONFIG)

groupMap = GROUP_MAP;

groupLoadingMap = {}
for groupId, modules of groupMap
  groupFile = "/assets/z/#{groupId}.js"
  for module in modules
    groupLoadingMap[module] = groupFile

require.config(groupLoadingMap: groupLoadingMap)

require ['cord!init/browserInit'], (browserInit) ->
  browserInit()
