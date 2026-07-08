import { Controller } from "@hotwired/stimulus"
import { application } from "controllers/application"

export default class extends Controller {
  connect() {
    this.previousSelections = new WeakMap()
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
      return
    }

    const inputName = selectRoot.dataset.flatPackSelectInputNameValue || target.name
    this.writeHiddenInputs(hiddenInputs, inputName, normalized)
    this.syncOptionState(selectRoot, normalized)
    this.syncChipState(selectRoot, normalized)
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
