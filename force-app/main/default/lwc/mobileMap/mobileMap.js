import { LightningElement, api, track } from "lwc";

const AUCKLAND_LAT = -36.8484597;
const AUCKLAND_LNG = 174.7633315;
const AUCKLAND_ZOOM = 11;
const MIN_ZOOM = 3;
const MAX_ZOOM = 20;

export default class MobileMaps extends LightningElement {
  // Markers
  @api formFactor;
  @api filteredMarkers = [];
  @api currentMarker;
  @api currentMarkerInd = 0;
  @api setCurrentMarker;
  @api redirectToMarkerDetails;
  @api routeToMarkerLocation;
  @api selfScheduleAppointment;
  @api handleError;
  resourceMarker;
  markersWithResource = [];
  located = true;
  useAucklandCenter = false;

  fallbackCenter = {
    location: {
      Latitude: AUCKLAND_LAT,
      Longitude: AUCKLAND_LNG
    }
  };

  @track showCard;
  @api currentMarkerSet(init) {
    if (!init) {
      this.located = false;
      this.useAucklandCenter = false;
    }
    this.setCardState(!init);
  }

  zoom = AUCKLAND_ZOOM;
  listView = "";

  renderedCallback() {
    const filtered = this.filteredMarkers || [];
    if (!this.isMarkersListEqual()) {
      this.markersWithResource = this.resourceMarker
        ? [...filtered, this.resourceMarker]
        : [...filtered];
    }
  }

  isMarkersListEqual() {
    const filtered = this.filteredMarkers || [];
    const markers = this.markersWithResource.filter(
      (m) => m.value !== undefined
    );
    return (
      filtered.length === markers.length &&
      filtered.every((m, ind) => m.value.id === markers[ind].value.id)
    );
  }

  @api setResourceMarker({ lat, lng }) {
    this.resourceMarker = {
      location: {
        Latitude: lat,
        Longitude: lng
      },
      mapIcon: this.getResourceMarkerSVG()
    };
  }

  onMarkerSelect(event) {
    try {
      if (!event.target.selectedMarkerValue) {
        return;
      }
      const ind = this.filteredMarkers.findIndex(
        (m) => m.value.id === event.target.selectedMarkerValue.id
      );
      this.setCurrentMarker(ind);
    } catch (error) {
      this.handleError(error);
    }
  }

  // Buttons Handlers

  handleLocatorClick() {
    this.zoom = AUCKLAND_ZOOM;
    this.setCardState(false);
    if (this.isDesktopForm) {
      this.located = false;
      this.useAucklandCenter = true;
      return;
    }
    this.useAucklandCenter = false;
    this.located = true;
  }

  handleZoomIn() {
    this.zoom = Math.min(MAX_ZOOM, (Number(this.zoom) || AUCKLAND_ZOOM) + 1);
  }

  handleZoomOut() {
    this.zoom = Math.max(MIN_ZOOM, (Number(this.zoom) || AUCKLAND_ZOOM) - 1);
  }

  handleCloseCardClick() {
    this.setCardState(false);
  }

  handleRedirectClick = () => {
    this.redirectToMarkerDetails();
  };

  handleRouteClick = () => {
    this.routeToMarkerLocation();
  };

  handleSelfScheduleClick = () => {
    this.selfScheduleAppointment();
  };

  handleBackCardClick() {
    const stackIndices = this.currentStackIndices;
    if (stackIndices.length > 1) {
      const currentPos = this.currentStackPosition;
      const previousPos =
        currentPos <= 0 ? stackIndices.length - 1 : currentPos - 1;
      this.setCurrentMarker(stackIndices[previousPos]);
      return;
    }
    let ind = this.currentMarkerInd - 1;
    if (ind < 0) {
      ind = this.filteredMarkers.length - 1;
    }
    this.setCurrentMarker(ind);
  }

  handleNextCardClick() {
    const stackIndices = this.currentStackIndices;
    if (stackIndices.length > 1) {
      const nextPos =
        (this.currentStackPosition + 1) % stackIndices.length;
      this.setCurrentMarker(stackIndices[nextPos]);
      return;
    }
    const ind = (this.currentMarkerInd + 1) % this.filteredMarkers.length;
    this.setCurrentMarker(ind);
  }

  // Getters & Helpers

  get isDesktopForm() {
    return this.formFactor === "Large" || this.formFactor === "Medium";
  }

  get containerClass() {
    const layout = this.isDesktopForm ? "Large" : "Small";
    return `main-container form-${layout}`;
  }

  get showDesktopMapControls() {
    return this.isDesktopForm;
  }

  get mapOptions() {
    return {
      disableDefaultUI: true,
      zoomControl: this.isDesktopForm
    };
  }

  get center() {
    if (this.useAucklandCenter) {
      return this.fallbackCenter;
    }
    if (this.located && this.resourceMarker) {
      return this.resourceMarker;
    }
    if (this.currentMarker?.location?.Latitude) {
      return this.currentMarker;
    }
    if (this.resourceMarker) {
      return this.resourceMarker;
    }
    return this.fallbackCenter;
  }

  get currentMarkerTitle() {
    return this.currentMarker?.value?.titleFieldValue;
  }

  get currentMarkerFirstDetailFieldName() {
    return this.currentMarker?.value?.firstDetailFieldLabel;
  }

  get currentMarkerFirstDetailFieldValue() {
    return this.currentMarker?.value?.firstDetailFieldValue;
  }

  get currentMarkerSecondDetailFieldName() {
    return this.currentMarker?.value?.secondDetailFieldLabel;
  }

  get currentMarkerSecondDetailFieldValue() {
    return this.currentMarker?.value?.secondDetailFieldValue;
  }

  get currentMarkerThirdDetailFieldName() {
    return this.currentMarker?.value?.thirdDetailFieldLabel;
  }

  get currentMarkerThirdDetailFieldValue() {
    return this.currentMarker?.value?.thirdDetailFieldValue;
  }

  get currentMarkerIndexUi() {
    const indUi = this.currentMarkerInd + 1;
    return isNaN(indUi) ? 0 : indUi;
  }

  get currentStackIndices() {
    const indices = this.currentMarker?.value?.stackIndices;
    return Array.isArray(indices) ? indices : [];
  }

  get currentStackCount() {
    return Number(this.currentMarker?.value?.stackCount) || 0;
  }

  get currentStackPosition() {
    const indices = this.currentStackIndices;
    const currentIndex = this.currentMarkerInd;
    const found = indices.indexOf(currentIndex);
    if (found >= 0) {
      return found;
    }
    return Number(this.currentMarker?.value?.stackIndex) || 0;
  }

  get footerLabel() {
    if (this.currentStackCount > 1) {
      return `${this.currentStackPosition + 1} of ${this.currentStackCount} at this location`;
    }
    return `${this.currentMarkerIndexUi} of ${this.filteredMarkers.length}`;
  }

  get currentMarkerDistance() {
    return this.currentMarker?.value?.distance;
  }

  get distanceLine() {
    const distance = this.currentMarkerDistance;
    return distance ? `Distance: ${distance}` : "Distance: —";
  }

  get cardClass() {
    const layout = this.isDesktopForm ? "Large" : "Small";
    return `cards form-${layout}`;
  }

  get cardFieldRows() {
    const fields = this.currentMarker?.value?.cardFields || [];
    const rows = [];
    const pending = [];
    fields.forEach((field, index) => {
      if (this.isFullWidthCardField(field)) {
        this.flushPairedFields(pending, rows);
        rows.push(this.buildCardRow(field, null, true, `card-row-${index}`));
        return;
      }
      pending.push(field);
      if (pending.length === 2) {
        this.flushPairedFields(pending, rows);
      }
    });
    this.flushPairedFields(pending, rows);
    return rows;
  }

  flushPairedFields(pending, rows) {
    if (pending.length === 0) {
      return;
    }
    const left = pending.shift();
    const right = pending.length > 0 ? pending.shift() : null;
    rows.push(
      this.buildCardRow(
        left,
        right,
        false,
        `card-row-${rows.length}-${left.label}`
      )
    );
  }

  buildCardRow(left, right, isFullWidth, key) {
    const leftValue = this.cardFieldDisplayValue(left);
    const telHref = this.toTelHref(left);
    return {
      key,
      isFullWidth,
      rowClass: isFullWidth
        ? "card-details-row card-details-row_full"
        : "card-details-row",
      leftText: this.formatCardField(left),
      rightText: this.formatCardField(right),
      leftLabel: left?.label || "",
      leftValue,
      leftIsPhone: !!(left?.isPhone && telHref),
      leftTelHref: telHref
    };
  }

  isFullWidthCardField(field) {
    if (!field) {
      return false;
    }
    if (field.isPhone) {
      return true;
    }
    const path = String(field.fieldApiName || "").toLowerCase();
    const label = String(field.label || "").toLowerCase();
    return (
      path === "contact.name" ||
      path === "contact.phone" ||
      path.endsWith(".phone") ||
      path.endsWith("phone") ||
      label.includes("phone") ||
      label.includes("contact name")
    );
  }

  cardFieldDisplayValue(field) {
    if (!field) {
      return "";
    }
    if (field.value == null || field.value === "") {
      return "—";
    }
    return field.value;
  }

  toTelHref(field) {
    if (!field?.isPhone) {
      return null;
    }
    const raw = this.cardFieldDisplayValue(field);
    if (!raw || raw === "—") {
      return null;
    }
    const digits = String(raw).replace(/[^\d+]/g, "");
    if (!digits) {
      return null;
    }
    return "tel:" + digits;
  }

  formatCardField(field) {
    if (!field) {
      return "";
    }
    return `${field.label}: ${this.cardFieldDisplayValue(field)}`;
  }

  get currentMarkerCanSelfSchedule() {
    return this.currentMarker?.value?.canSelfSchedule !== false;
  }

  get selectedMarkerValue() {
    return this.currentMarker?.value;
  }

  get currentMarkerIconUrl() {
    return this.currentMarker?.value?.iconUrl;
  }

  setCardState = (state) => {
    this.showCard = state;
  };

  getResourceMarkerSVG() {
    const icon = `<svg width="32" height="32" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg">
                <g filter="url(#filter0_d_2956_82705)">
                    <rect x="4" width="24" height="24" rx="12" fill="white" shape-rendering="crispEdges"/>
                    <rect x="8" y="4" width="16" height="16" rx="8" fill="#0176D3"/>
                </g>
                <defs>
                    <filter id="filter0_d_2956_82705" x="0" y="0" width="32" height="32" filterUnits="userSpaceOnUse" color-interpolation-filters="sRGB">
                        <feFlood flood-opacity="0" result="BackgroundImageFix"/>
                        <feColorMatrix in="SourceAlpha" type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 127 0" result="hardAlpha"/>
                        <feOffset dy="4"/>
                        <feGaussianBlur stdDeviation="2"/>
                        <feComposite in2="hardAlpha" operator="out"/>
                        <feColorMatrix type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.25 0"/>
                        <feBlend mode="normal" in2="BackgroundImageFix" result="effect1_dropShadow_2956_82705"/>
                        <feBlend mode="normal" in="SourceGraphic" in2="effect1_dropShadow_2956_82705" result="shape"/>
                    </filter>
                </defs>
            </svg>`;
    return "data:image/svg+xml;charset=UTF-8," + encodeURIComponent(icon);
  }
}
