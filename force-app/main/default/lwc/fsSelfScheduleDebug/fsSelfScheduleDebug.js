import { LightningElement, api } from "lwc";

export default class FsSelfScheduleDebug extends LightningElement {
  @api visible = false;
  @api resourceId;
  @api latitude;
  @api longitude;
  @api diagnosticRows = [];
  @api diagnosticErrors = [];
  @api executionTrace = [];
  @api displaySoql = "";
  @api fieldAccessRows = [];

  get hasErrors() {
    return (this.diagnosticErrors || []).length > 0;
  }

  get hasDisplaySoql() {
    return !!(this.displaySoql && String(this.displaySoql).trim());
  }

  get hasFieldAccessRows() {
    return (this.fieldAccessRows || []).length > 0;
  }

  get resourceDisplayInfo() {
    return {
      primaryField: "Name"
    };
  }

  get resourceMatchingInfo() {
    return {
      primaryField: { fieldPath: "Name" }
    };
  }

  get resourceFilter() {
    return {
      criteria: [
        {
          fieldPath: "IsActive",
          operator: "eq",
          value: true
        }
      ]
    };
  }

  handleResourceChange(event) {
    this.dispatchEvent(
      new CustomEvent("debuginput", {
        detail: {
          field: "resourceId",
          value: event.detail.recordId || ""
        }
      })
    );
  }

  handleInputChange(event) {
    this.dispatchEvent(
      new CustomEvent("debuginput", {
        detail: {
          field: event.target.dataset.field,
          value: event.target.value
        }
      })
    );
  }

  handleApply() {
    this.dispatchEvent(new CustomEvent("debugapply"));
  }

  handleHide() {
    this.dispatchEvent(new CustomEvent("debughide"));
  }
}
