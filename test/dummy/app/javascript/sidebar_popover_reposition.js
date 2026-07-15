const SIDEBAR_TARGET_SELECTOR = '[data-flat-pack--sidebar-layout-target="sidebar"]'
const SIDEBAR_TOGGLE_SELECTOR = [
  '[data-action*="flat-pack--sidebar-layout#toggleDesktop"]',
  '[data-action*="flat-pack--sidebar-layout#toggleMobile"]'
].join(',')

if (!window.__flatPackSidebarPopoverRepositionBound) {
  window.__flatPackSidebarPopoverRepositionBound = true

  let pulseIntervalId = null
  let pulseTimeoutId = null

  const emitResize = () => {
    window.dispatchEvent(new Event("resize"))
  }

  const stopPulse = () => {
    if (pulseIntervalId) {
      clearInterval(pulseIntervalId)
      pulseIntervalId = null
    }
    if (pulseTimeoutId) {
      clearTimeout(pulseTimeoutId)
      pulseTimeoutId = null
    }
  }

  const startPulse = () => {
    stopPulse()
    emitResize()

    // Sidebar width/transform animation runs ~300ms in FlatPack.
    pulseIntervalId = window.setInterval(emitResize, 50)
    pulseTimeoutId = window.setTimeout(() => {
      stopPulse()
      emitResize()
    }, 380)
  }

  document.addEventListener(
    "click",
    (event) => {
      if (event.target.closest(SIDEBAR_TOGGLE_SELECTOR)) {
        startPulse()
      }
    },
    true
  )

  document.addEventListener(
    "transitionend",
    (event) => {
      if (event.target.closest?.(SIDEBAR_TARGET_SELECTOR)) {
        stopPulse()
        emitResize()
      }
    },
    true
  )
}
