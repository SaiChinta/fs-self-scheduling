import { LightningElement, api } from "lwc";

const IOS_MARGIN = "34px";
const COLLAPSE_HEIGHT_SETTLE_MS = 800;
const LARGE_EXPAND_OFFSET = "20%";

export default class LocationsList extends LightningElement {
  @api formFactor;
  @api filteredMarkers;
  @api currentObject;
  @api setCurrentMarker;
  @api redirectToMarkerDetails;
  @api routeToMarkerLocation;
  @api selfScheduleAppointment;
  @api isIos;
  @api handleError;

  mainTemplate;
  headerElement;
  listElement;

  showPopover = false;
  actionButtonIndexClicked;

  init = false;
  expanded = false;
  dragTouchStart;
  listHeightTimer;

  renderedCallback() {
    this.mainTemplate = this.template.querySelector(".main-container");
    this.headerElement = this.template.querySelector(".header");
    this.listElement = this.template.querySelector(".list");
    if (this.listElement) {
      this.listElement.style.paddingBottom = this.isIos?.() ? IOS_MARGIN : "0";
    }
    if (!this.init && this.headerElement) {
      this.detectDrag();
      this.init = true;
    }
  }

  disconnectedCallback() {
    window.clearTimeout(this.listHeightTimer);
    if (this.headerElement && this.dragTouchStart) {
      this.headerElement.removeEventListener("touchstart", this.dragTouchStart);
    }
  }

  @api currentMarkerSet() {
    this.closeLocationsList();
  }

  handleItemClick = (e) => {
    try {
      e.preventDefault();
      e.stopPropagation();
      const index = e?.currentTarget?.dataset?.index;
      if (index !== undefined) {
        this.setCurrentMarker(parseInt(index, 10));
      }
    } catch (error) {
      this.handleError(error);
    }
  };

  handleActionsButtonClick = (e) => {
    try {
      e.stopPropagation();
      const el = e.currentTarget;
      const markerInd = parseInt(el.closest("li")?.dataset?.index, 10);
      const popover = this.template.querySelector(".popover-container");
      if (popover && this.listElement) {
        const offset =
          el.offsetParent?.offsetHeight -
          el.offsetTop -
          el.offsetHeight +
          this.listElement.scrollTop;
        popover.style.bottom = `${offset}px`;
      }
      if (!this.showPopover || markerInd === this.actionButtonIndexClicked) {
        this.showPopover = !this.showPopover;
      }
      this.actionButtonIndexClicked = markerInd;
    } catch (error) {
      this.handleError(error);
    }
  };

  handlePopoverMaskClick = () => {
    this.showPopover = false;
  };

  handleGrabberClick = () => {
    if (this.expanded) {
      this.closeLocationsList();
      return;
    }
    if (this.listElement) {
      this.listElement.style.height = "auto";
    }
    this.openLocationsList();
  };

  handleHeaderKeydown = (event) => {
    if (event.key !== "Enter" && event.key !== " ") {
      return;
    }
    event.preventDefault();
    this.handleGrabberClick();
  };

  handleViewClick = () => {
    this.redirectToMarkerDetails(this.actionButtonIndexClicked);
    this.showPopover = false;
  };

  handleDirectionsClick = () => {
    this.routeToMarkerLocation(this.actionButtonIndexClicked);
    this.showPopover = false;
  };

  handleSelfScheduleClick = () => {
    this.selfScheduleAppointment(this.actionButtonIndexClicked);
    this.showPopover = false;
  };

  get loaded() {
    return !!this.currentObject?.label;
  }

  get isLargeForm() {
    return this.formFactor === "Large";
  }

  get expandedAria() {
    return this.expanded ? "true" : "false";
  }

  get popoverClass() {
    return this.showPopover ? "popover-shown" : "popover-hidden";
  }

  get titleObjectText() {
    if (!this.currentObject?.label) {
      return "Locations";
    }
    return this.filteredMarkers?.length === 1
      ? this.currentObject.label
      : this.currentObject.plural;
  }

  get listItems() {
    return (this.filteredMarkers || []).map((marker, index) => ({
      id: marker.value?.id || `marker-${index}`,
      index,
      iconUrl: marker.value?.iconUrl,
      color: marker.value?.color,
      title: marker.value?.titleFieldValue,
      subtitle: this.buildSubtitle(marker)
    }));
  }

  buildSubtitle(marker) {
    const parts = [];
    const distance = marker.value?.distance;
    const subject = marker.value?.firstDetailFieldValue;
    if (distance) {
      parts.push(distance);
    }
    if (subject) {
      parts.push(subject);
    }
    const workType = this.cardFieldValue(marker, "Work Type");
    if (workType) {
      parts.push(workType);
    }
    const duration =
      this.cardFieldValue(marker, "Duration(Mins)") ||
      this.fallbackDuration(marker);
    if (duration) {
      parts.push(duration);
    }
    return parts.join(" • ");
  }

  cardFieldValue(marker, label) {
    const fields = marker.value?.cardFields || [];
    const match = fields.find((field) => {
      const fieldLabel = String(field.label || "").toLowerCase();
      const wanted = String(label || "").toLowerCase();
      if (fieldLabel === wanted) {
        return true;
      }
      return (
        wanted.indexOf("duration") === 0 && fieldLabel.indexOf("duration") === 0
      );
    });
    const value = match?.value;
    if (!value || value === "—") {
      return "";
    }
    return String(value);
  }

  fallbackDuration(marker) {
    const minutes = marker.value?.durationInMinutes;
    if (minutes == null || minutes === "") {
      return "";
    }
    return String(minutes);
  }

  get containerHeight() {
    return this.getBoundingClientRect().height || window.innerHeight;
  }

  openLocationsList() {
    if (!this.mainTemplate || !this.listElement) {
      return;
    }
    const top = this.mainTemplate.style.top;
    this.expanded = true;
    if (this.isLargeForm) {
      this.mainTemplate.style.transform = `translateY(calc(${LARGE_EXPAND_OFFSET} - ${top}))`;
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      this.listHeightTimer = window.setTimeout(() => {
        this.setListHeight();
      }, 50);
      return;
    }
    if (this.listElement.clientHeight > (this.containerHeight * 85) / 100) {
      this.mainTemplate.style.transform = `translateY(calc(20% - ${top}))`;
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      this.listHeightTimer = window.setTimeout(() => {
        this.setListHeight();
      }, COLLAPSE_HEIGHT_SETTLE_MS);
    } else {
      this.mainTemplate.style.transform = `translateY(calc((90% - ${this.listElement.clientHeight}px) - ${top}))`;
    }
  }

  closeLocationsList() {
    if (!this.mainTemplate) {
      return;
    }
    const top = this.mainTemplate.style.top;
    this.expanded = false;
    this.mainTemplate.style.transform = `translateY(calc(85% - ${top}))`;
    this.showPopover = false;
    if (this.listElement) {
      this.listElement.style.height = "auto";
    }
  }

  setListHeight() {
    if (!this.listElement) {
      return;
    }
    const hostBounds = this.getBoundingClientRect();
    const listBounds = this.listElement.getBoundingClientRect();
    const newHeight = hostBounds.bottom - listBounds.top;
    this.listElement.style.height = `${newHeight}px`;
  }

  detectDrag = () => {
    let verticalDelta = 0;
    let startY = 0;

    const dragMove = (e) => {
      e.preventDefault();
      verticalDelta = startY - e.touches[0].clientY;
      startY = e.touches[0].clientY;
      this.mainTemplate.style.top = `${
        this.mainTemplate.offsetTop - verticalDelta
      }px`;
    };

    const dragEnd = () => {
      if (verticalDelta > 0) {
        this.openLocationsList();
      } else {
        this.closeLocationsList();
      }
      this.headerElement.removeEventListener("touchend", dragEnd);
      this.headerElement.removeEventListener("touchmove", dragMove);
    };

    this.dragTouchStart = (e) => {
      this.listElement.style.height = "auto";
      this.showPopover = false;
      e.preventDefault();
      startY = e.touches[0].clientY;
      this.headerElement.addEventListener("touchend", dragEnd);
      this.headerElement.addEventListener("touchmove", dragMove);
    };

    this.headerElement.addEventListener("touchstart", this.dragTouchStart);
  };
}
