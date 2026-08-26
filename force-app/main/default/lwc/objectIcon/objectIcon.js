import { LightningElement, api } from "lwc";

export default class ObjectIcon extends LightningElement {
  @api iconUrl;
  @api color;

  renderedCallback() {
    const icon = this.template.querySelector("img");
    if (icon && this.color) {
      icon.style.backgroundColor = this.color;
    }
  }
}
