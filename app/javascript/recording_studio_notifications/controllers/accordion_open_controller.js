import { Controller } from "@hotwired/stimulus"

// Flatpack writes the initial state to data-flat-pack--accordion-open.
// That double hyphen is dataset["flatPack-AccordionOpen"], and the accordion
// controller reads dataset.flatPackAccordionOpen, so connect closes every
// panel. Reopen the marked panels once, then leave clicks alone.
export default class extends Controller {
  connect() {
    this.restoreIfClosed()
    this.observer = new MutationObserver(() => this.restoreIfClosed())
    this.observer.observe(this.element, {
      subtree: true,
      attributes: true,
      attributeFilter: ["hidden", "aria-expanded", "style"]
    })
    requestAnimationFrame(() => this.restoreIfClosed())
  }

  disconnect() {
    this.observer?.disconnect()
  }

  restoreIfClosed() {
    if (this.settled || this.restoring) return

    const panels = this.element.querySelectorAll("[data-flat-pack--accordion-open='true']")
    const closed = [...panels].some((panel) => this.closed(panel))
    if (!closed) return

    this.restoring = true
    panels.forEach((panel) => this.open(panel))
    this.restoring = false
    this.settled = true
    this.observer?.disconnect()
  }

  closed(panel) {
    return panel.hidden || panel.style.maxHeight === "0px" || panel.getAttribute("aria-expanded") === "false"
  }

  open(panel) {
    panel.hidden = false
    panel.style.maxHeight = "none"
    panel.setAttribute("aria-expanded", "true")

    const trigger = panel.parentElement?.querySelector("[data-flat-pack--accordion-target='trigger']")
    if (trigger) trigger.setAttribute("aria-expanded", "true")

    const icon = panel.parentElement?.querySelector("[data-flat-pack--accordion-target='icon']")
    if (icon) icon.style.transform = "rotate(180deg)"
  }
}
