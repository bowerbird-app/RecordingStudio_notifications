import { Controller } from "@hotwired/stimulus"
import { application } from "controllers/application"

const REQUIRED_CHANNEL_TOOLTIP = "This channel can't be removed"

export default class extends Controller {
  static values = {
    requiredChannels: { type: Object, default: {} }
  }

  connect() {
    this.previousSelections = new WeakMap()
    requestAnimationFrame(() => this.decorateRequiredChips())
  }

  syncNoneSelection(event) {
    const target = event.target
    if (!(target instanceof HTMLInputElement)) return
    if (target.type !== "hidden") return
    if (!target.name.startsWith("preferences[")) return

    const selectRoot = target.closest("[data-controller~='flat-pack--select']")
    if (!selectRoot) return

    const hiddenInputs = selectRoot.querySelector("[data-flat-pack--select-target='hiddenInputs']")
    if (!hiddenInputs) return

    const values = this.hiddenValues(hiddenInputs)
    const previous = this.previousSelections.get(selectRoot) || new Set()

    const normalized = this.normalizedValues(values, previous)
    this.previousSelections.set(selectRoot, new Set(normalized))

    if (this.sameValues(values, normalized)) return

    const flatPackSelectController = application.getControllerForElementAndIdentifier(
      selectRoot,
      "flat-pack--select"
    )

    if (flatPackSelectController) {
      flatPackSelectController.selectedValues = new Set(normalized)
      flatPackSelectController.syncSelectedState()
      this.decorateRequiredChips()
      return
    }

    const inputName = selectRoot.dataset.flatPackSelectInputNameValue || target.name
    this.writeHiddenInputs(hiddenInputs, inputName, normalized)
    this.syncOptionState(selectRoot, normalized)
    this.syncChipState(selectRoot, normalized)
    this.decorateRequiredChips()
  }

  decorateRequiredChips() {
    this.element.querySelectorAll("[data-controller~='flat-pack--select']").forEach((selectRoot) => {
      const typeKey = this.typeKeyForSelect(selectRoot)
      if (!typeKey) return

      const required = new Set((this.requiredChannelsValue[typeKey] || []).map(String))

      this.removeRequiredOptions(selectRoot, required)

      selectRoot.querySelectorAll("[data-flat-pack--select-target='chip']").forEach((chip) => {
        if (!required.has(chip.dataset.value)) return

        chip.querySelectorAll("[data-action*='removeChip']").forEach((removeControl) => {
          removeControl.remove()
        })

        if (chip.dataset.requiredChannelDecorated === "true") return

        const chipVisual = chip.querySelector(".inline-flex.items-center")
        if (chipVisual) {
          chipVisual.dataset.tooltip = REQUIRED_CHANNEL_TOOLTIP
          chipVisual.setAttribute("aria-label", REQUIRED_CHANNEL_TOOLTIP)
          chipVisual.setAttribute("tabindex", "0")
          chipVisual.classList.add("rsn-required-channel-chip")
        }

        chip.dataset.requiredChannelDecorated = "true"
      })
    })
  }

  removeRequiredOptions(selectRoot, required) {
    if (required.size === 0) return

    const optionsList = selectRoot.querySelector("[data-flat-pack--select-target='optionsList']")
    if (!optionsList) return

    required.forEach((channel) => {
      optionsList.querySelectorAll(`[role='option'][data-value='${CSS.escape(channel)}']`).forEach((option) => {
        option.remove()
      })
    })

    optionsList.dataset.resultsCount = String(optionsList.querySelectorAll("[role='option']").length)
  }

  typeKeyForSelect(selectRoot) {
    const inputName =
      selectRoot.dataset.flatPackSelectInputNameValue ||
      selectRoot.querySelector("input[type='hidden']")?.name

    if (!inputName) return null

    const match = inputName.match(/preferences\[([^\]]+)\]/)
    return match ? match[1] : null
  }

  hiddenValues(hiddenInputs) {
    return Array.from(hiddenInputs.querySelectorAll("input[type='hidden']"))
      .map((input) => input.value)
      .filter((value) => value !== "")
  }

  normalizedValues(values, previous) {
    if (!values.includes("__none__") || values.length <= 1) {
      return values
    }

    const added = values.filter((value) => !previous.has(value))

    if (added.includes("__none__")) {
      return ["__none__"]
    }

    return values.filter((value) => value !== "__none__")
  }

  sameValues(left, right) {
    if (left.length !== right.length) return false
    return left.every((value, index) => value === right[index])
  }

  writeHiddenInputs(hiddenInputs, inputName, values) {
    hiddenInputs.innerHTML = ""

    if (values.length === 0) {
      const emptyInput = document.createElement("input")
      emptyInput.type = "hidden"
      emptyInput.name = inputName
      emptyInput.value = ""
      hiddenInputs.appendChild(emptyInput)
      return
    }

    values.forEach((value) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = inputName
      input.value = value
      hiddenInputs.appendChild(input)
    })
  }

  syncOptionState(selectRoot, selectedValues) {
    const selectedSet = new Set(selectedValues)
    const options = selectRoot.querySelectorAll("[role='option'][data-value]")

    options.forEach((option) => {
      const isSelected = selectedSet.has(option.dataset.value)
      option.setAttribute("aria-selected", String(isSelected))

      if (isSelected) {
        option.classList.add("bg-[var(--color-primary)]", "text-white")
        option.classList.remove("hover:bg-[var(--surface-muted-background-color)]", "text-[var(--surface-content-color)]")
      } else {
        option.classList.remove("bg-[var(--color-primary)]", "text-white")
        option.classList.add("hover:bg-[var(--surface-muted-background-color)]", "text-[var(--surface-content-color)]")
      }
    })
  }

  syncChipState(selectRoot, selectedValues) {
    const selectedSet = new Set(selectedValues)
    const chips = selectRoot.querySelectorAll("[data-flat-pack--select-target='chip']")
    chips.forEach((chip) => {
      chip.classList.toggle("hidden", !selectedSet.has(chip.dataset.value))
    })

    const placeholder = selectRoot.querySelector("[data-flat-pack--select-target='placeholder']")
    if (placeholder) {
      placeholder.classList.toggle("hidden", selectedValues.length > 0)
    }
  }
}
