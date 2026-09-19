import { Controller } from "@hotwired/stimulus"

// A date input only opens its calendar when you hit the little icon, which is a
// small target and not obvious. This opens it wherever you click in the field.
export default class extends Controller {
  open() {
    try {
      this.element.showPicker()
    } catch {
      // showPicker throws if the browser does not support it, or if the call
      // was not triggered by a real user gesture. Either way the field still
      // works as a normal date input, so there is nothing to handle.
    }
  }
}
