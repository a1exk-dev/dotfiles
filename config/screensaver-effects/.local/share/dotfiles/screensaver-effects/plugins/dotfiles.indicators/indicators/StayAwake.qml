import QtQuick
import qs.Ui

BarIndicator {
  id: root

  readonly property string idleServiceId: bar?.shell?.pluginRegistry?.resolveEnabledId("omarchy.idle") || "omarchy.idle"
  readonly property var idleService: bar?.shell?.serviceFor(idleServiceId)

  active: idleService ? idleService.stayAwake : false
  activeText: "󰅶"
  inactiveText: "󰅶"
  activeTooltipText: "Allow Idle Lock & Screensaver"
  inactiveTooltipText: "Stay Awake"

  function toggle() {
    if (root.idleService) root.idleService.setIdleEnabled(root.active)
  }

  onPressed: function() { root.toggle() }
}
