import { LightningElement, wire } from "lwc";
import { getObjectInfos } from "lightning/uiObjectInfoApi";
import { NavigationMixin } from "lightning/navigation";
import {
  IsConsoleNavigation,
  openTab
} from "lightning/platformWorkspaceApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import FORM_FACTOR from "@salesforce/client/formFactor";
import getMapAppointments from "@salesforce/apex/FsSSMapLayersService.getMapAppointments";
import getResourceContext from "@salesforce/apex/FsSSMapLayersService.getResourceContext";
import getConfig from "@salesforce/apex/FsSSMapLayersService.getConfig";
import selfSchedule from "@salesforce/apex/FsSSMapLayersService.selfSchedule";
import { config as staticConfig } from "./config";
import { normalizeConfig } from "./fsSSConfig";
import { haversine, formatDistance } from "./fsSSGeo";
import ConfirmModal from "c/confirmModal";

const AUCKLAND_LAT = -36.8484597;
const AUCKLAND_LNG = 174.7633315;
const GPS_TIMEOUT_MS = 8000;

/**
 * @description Self-scheduling map. Loads unassigned Service Appointments inside
 *              a radius of the current origin. Origin defaults to Auckland CBD.
 */
export default class MobileMapLayersMain extends NavigationMixin(
  LightningElement
) {
  CONFIG = JSON.parse(JSON.stringify(staticConfig));
  settings = normalizeConfig({});
  formFactor = FORM_FACTOR;
  resourceId;
  resourceName = "";
  resourceLocation = {
    lat: String(AUCKLAND_LAT),
    lng: String(AUCKLAND_LNG)
  };
  locationSource = "auckland-default";
  allMarkers = [];
  filteredMarkers = [];
  currentMarker;
  currentMarkerInd = 0;
  currentObjectFilter = {
    value: "ServiceAppointment",
    label: "Service Appointment",
    plural: "Service Appointments",
    iconUrl: "",
    color: "#0176d3"
  };
  claimedAppointmentIds = new Set();
  debugVisible = false;
  listErrorsVisible = false;
  debugResourceId = "";
  debugLatitude = "";
  debugLongitude = "";
  debugAppliedResourceId;
  tapTimes = [];
  diagnosticRows = [];
  diagnosticErrors = [];
  executionTrace = [];
  displaySoql = "";
  lastBooleanClause = "";
  lastBindStatuses = "";
  lastBindRadius = "";
  lastBindRowLimit = "";
  lastMatchedResourceId = "";
  lastPolicyMatchingApplied = "";
  lastRadiusRowCount = "";
  lastSkippedTerritoryCount = "";
  lastSkippedSkillCount = "";
  lastPolicyRuleTypes = "";
  lastUnimplementedRuleTypes = "";
  overlappingLocationCount = 0;
  queriedObjects;
  markerLoadInFlight = false;
  markerLoadQueued = false;

  mapOriginSynced = false;

  connectedCallback() {
    this.log("connectedCallback", {
      formFactor: this.formFactor,
      online: navigator.onLine,
      origin: this.originLabel
    });
    this.queriedObjects = this.CONFIG.mapObjects.map((item) => item.value);
    this.currentObjectFilter = {
      ...this.currentObjectFilter,
      ...this.CONFIG.mapObjects[0]
    };
    this.refreshDiagnostics();
    this.loadConfig();
    this.loadResourceContext();
    this.resolveDeviceLocation();
    this.refreshMarkers();
  }

  renderedCallback() {
    if (!this.mapOriginSynced) {
      this.mapOriginSynced = true;
      this.syncMapOrigin();
    }
  }

  @wire(IsConsoleNavigation)
  isConsoleNavigation;

  @wire(getObjectInfos, { objectApiNames: "$queriedObjects" })
  wiredObjectInfos({ data, error }) {
    if (data) {
      this.log("getObjectInfos", { results: data.results?.length });
      this.applyObjectInfo(data);
    } else if (error) {
      this.log("getObjectInfos failed", this.toErrorMessage(error));
      this.recordError("getObjectInfos", error);
    }
  }

  get currentObject() {
    return this.currentObjectFilter;
  }

  get isDesktopForm() {
    return this.formFactor === "Large" || this.formFactor === "Medium";
  }

  get showDebugChip() {
    return this.settings.debugEnabled;
  }

  get radiusLabel() {
    return `${this.settings.searchRadius} ${this.settings.distanceUnit}`;
  }

  get originLabel() {
    return `${this.resourceLocation.lat}, ${this.resourceLocation.lng}`;
  }

  get searchSummary() {
    return `Within ${this.radiusLabel} of ${this.locationSource}`;
  }

  get containerClass() {
    const layout = this.isDesktopForm ? "Large" : "Small";
    return `find-nearby-main-container form-${layout}`;
  }

  get bannerUserName() {
    const userName = this.settings.userName || "";
    if (this.debugAppliedResourceId && this.resourceName) {
      return `${userName} (${this.resourceName})`.trim();
    }
    return userName;
  }

  get bannerOrigin() {
    return `Query origin: ${this.originLabel} (${this.locationSource})`;
  }

  get fieldAccessRows() {
    return (this.settings.cardFieldAccess || []).map((row, index) => {
      const accessible = row.accessible === true;
      return {
        key: "fa-" + index,
        label: `${row.label || ""} (${row.fieldApiName || ""})`.trim(),
        status: accessible ? "Accessible" : "Not accessible",
        statusClass: accessible ? "access-ok" : "access-bad",
        detail: row.reason && row.reason !== "Accessible" ? row.reason : ""
      };
    });
  }

  async loadConfig() {
    this.log("loadConfig", "calling Apex getConfig");
    try {
      this.settings = normalizeConfig(await getConfig());
      this.debugVisible = this.settings.debugEnabled;
      this.log("loadConfig ok", {
        searchRadius: this.settings.searchRadius,
        distanceUnit: this.settings.distanceUnit,
        statusValues: this.settings.statusValues,
        debugEnabled: this.settings.debugEnabled,
        maxResults: this.settings.maxResults
      });
      this.refreshDiagnostics();
      this.refreshMarkers();
    } catch (error) {
      this.log("loadConfig failed", this.toErrorMessage(error));
      this.recordError("getConfig", error);
    }
  }

  async handleRefresh(event) {
    event.stopPropagation();
    this.claimedAppointmentIds = new Set();
    this.diagnosticErrors = [];
    this.listErrorsVisible = false;
    this.log("refresh", "reloading config, resource, and markers");
    await this.loadConfig();
    await this.loadResourceContext();
    this.resolveDeviceLocation();
  }

  async loadResourceContext() {
    this.log("loadResourceContext", {
      resourceId: this.debugAppliedResourceId || "running-user"
    });
    try {
      const context = await getResourceContext({
        resourceId: this.debugAppliedResourceId || null
      });
      if (!context) {
        this.log(
          "loadResourceContext",
          "no Service Resource linked; keeping current origin"
        );
        this.refreshDiagnostics();
        return;
      }
      this.resourceId = context.resourceId;
      this.resourceName = context.resourceName || "";
      if (!this.debugAppliedResourceId) {
        this.debugResourceId = context.resourceId;
      }
      this.log("loadResourceContext ok", context);
      this.applyResourceLocation(context);
      this.refreshMarkers();
    } catch (error) {
      this.log("loadResourceContext failed", this.toErrorMessage(error));
      this.recordError("getResourceContext", error);
    }
  }

  applyResourceLocation(context) {
    if (
      this.locationSource === "device" ||
      this.locationSource === "debug" ||
      context.latitude == null ||
      context.longitude == null
    ) {
      return;
    }
    this.resourceLocation = {
      lat: String(context.latitude),
      lng: String(context.longitude)
    };
    this.locationSource = this.debugAppliedResourceId
      ? "debug-resource"
      : "service-resource";
    this.log("origin updated from Service Resource", this.originLabel);
    this.syncMapOrigin();
    this.refreshDiagnostics();
  }

  resolveDeviceLocation() {
    if (!navigator.geolocation) {
      this.log("geolocation", "navigator.geolocation is not available");
      return;
    }
    this.log("geolocation", "requesting current position");
    navigator.geolocation.getCurrentPosition(
      (position) => {
        if (this.locationSource === "debug") {
          this.log("geolocation ignored; debug origin is active");
          return;
        }
        this.resourceLocation = {
          lat: String(position.coords.latitude),
          lng: String(position.coords.longitude)
        };
        this.locationSource = "device";
        this.log("geolocation ok", this.originLabel);
        this.syncMapOrigin();
        this.refreshDiagnostics();
        this.refreshMarkers();
      },
      (error) => {
        this.log("geolocation failed", error?.message || "unavailable");
        this.recordError("geolocation", error?.message || "unavailable");
      },
      { enableHighAccuracy: true, timeout: GPS_TIMEOUT_MS, maximumAge: 30000 }
    );
  }

  applyObjectInfo(data) {
    const results = data.results || [];
    this.CONFIG.mapObjects.forEach((objectDef) => {
      const objResult = results.find(
        (entry) => entry.result?.apiName === objectDef.value
      )?.result;
      if (!objResult) {
        return;
      }
      objectDef.label = objResult.label;
      objectDef.plural = objResult.pluralLabel;
      objectDef.iconUrl = objResult.themeInfo?.iconUrl;
      objectDef.color = `#${objResult.themeInfo?.color ?? "0176d3"}`;
    });
    if (this.CONFIG.mapObjects[0]) {
      this.currentObjectFilter = { ...this.CONFIG.mapObjects[0] };
    }
  }

  async refreshMarkers() {
    if (this.markerLoadInFlight) {
      this.markerLoadQueued = true;
      this.log("refreshMarkers", "queued; a load is already in flight");
      return;
    }
    this.markerLoadInFlight = true;
    try {
      await this.loadApexAppointments();
    } finally {
      this.markerLoadInFlight = false;
    }
    if (this.markerLoadQueued) {
      this.markerLoadQueued = false;
      await this.refreshMarkers();
    }
  }

  async loadApexAppointments() {
    const latitude = Number(this.resourceLocation.lat);
    const longitude = Number(this.resourceLocation.lng);
    this.log("getMapAppointments request", {
      latitude,
      longitude,
      resourceId: this.resourceId,
      radius: this.radiusLabel
    });
    try {
      const result =
        (await getMapAppointments({
          latitude,
          longitude,
          resourceId: this.resourceId
        })) || {};
      const rows = result.appointments || [];
      this.displaySoql = result.soqlForDisplay || result.soql || "";
      this.lastBooleanClause = result.booleanClause || "(none)";
      this.lastBindStatuses = (result.bindStatuses || []).join(", ") || "(none)";
      this.lastBindRadius =
        result.bindRadius == null ? "" : String(result.bindRadius);
      this.lastBindRowLimit =
        result.bindRowLimit == null ? "" : String(result.bindRowLimit);
      this.lastMatchedResourceId = result.matchedResourceId || "(none)";
      this.lastPolicyMatchingApplied =
        result.policyMatchingApplied == null
          ? "(none)"
          : String(result.policyMatchingApplied);
      this.lastRadiusRowCount =
        result.radiusRowCount == null ? "" : String(result.radiusRowCount);
      this.lastSkippedTerritoryCount =
        result.skippedTerritoryCount == null
          ? "0"
          : String(result.skippedTerritoryCount);
      this.lastSkippedSkillCount =
        result.skippedSkillCount == null
          ? "0"
          : String(result.skippedSkillCount);
      this.lastPolicyRuleTypes = (result.policyRuleTypes || []).join(", ") || "(none)";
      this.lastUnimplementedRuleTypes =
        (result.unimplementedRuleTypes || []).join(", ") || "(none)";
      this.log("getMapAppointments returned", {
        count: result.rowCount,
        radiusRowCount: result.radiusRowCount,
        matchingApplied: result.policyMatchingApplied,
        matchedResourceId: result.matchedResourceId,
        soqlLength: (result.soql || "").length
      });
      const records = rows
        .filter((row) => !this.claimedAppointmentIds.has(row.id))
        .map((row) => ({
          ...row,
          status: row.secondDetailFieldValue,
          distance: haversine(
            latitude,
            longitude,
            Number(row.latitude),
            Number(row.longitude),
            this.settings.distanceUnit
          )
        }));
      this.renderRecords(records);
      this.refreshDiagnostics(rows.length, records.length);
    } catch (error) {
      this.log("getMapAppointments failed", this.toErrorMessage(error));
      this.recordError("getMapAppointments", error);
      this.handleError(error);
    }
  }

  renderRecords(records) {
    const objectDef = this.currentObjectFilter;
    this.allMarkers = records.map((record) =>
      this.createMarker(objectDef, record)
    );
    this.applyLocationStacks(this.allMarkers);
    this.filteredMarkers = [...this.allMarkers];
    this.setCurrentMarker(0, true);
    this.log("renderRecords", { markers: this.filteredMarkers.length });
  }

  createMarker(objDetails, recordDetails) {
    const lat = recordDetails.latitude;
    const long = recordDetails.longitude;
    return {
      location: { Latitude: lat, Longitude: long },
      mapIcon: this.getMarkerSVG(objDetails.color || "#0176d3"),
      value: {
        ...objDetails,
        ...recordDetails,
        navUrl: `com.salesforce.fieldservice://v1/sObject/${recordDetails.id}/details`,
        routeUrl: `https://www.google.com/maps/dir/?api=1&destination=${lat},${long}`,
        distance: formatDistance(
          recordDetails.distance,
          this.settings.distanceUnit
        ),
        canSelfSchedule: !this.claimedAppointmentIds.has(recordDetails.id)
      }
    };
  }

  setCurrentMarker = (ind, init = false) => {
    this.currentMarkerInd = ind;
    this.currentMarker = this.filteredMarkers[ind]
      ? { ...this.filteredMarkers[ind] }
      : undefined;
    this.template.querySelector("c-locations-list")?.currentMarkerSet();
    this.template.querySelector("c-mobile-map")?.currentMarkerSet(init);
    this.syncMapOrigin();
  };

  syncMapOrigin() {
    this.template.querySelector("c-mobile-map")?.setResourceMarker({
      lat: this.resourceLocation.lat,
      lng: this.resourceLocation.lng
    });
  }

  redirectToMarkerDetails = async (ind) => {
    const index = ind ?? this.currentMarkerInd;
    this.log("open record", this.filteredMarkers[index]?.value?.id);
    let toOpen = true;
    if (this.isIos()) {
      toOpen = await ConfirmModal.open({
        size: "small",
        content: "Opening the record resets your search.",
        header: "Open Record?",
        okButtonText: "Open Record",
        cancelButtonText: "Cancel"
      });
    }
    if (toOpen && this.filteredMarkers[index]?.value?.id) {
      await this.openAppointmentRecord(this.filteredMarkers[index].value.id);
    }
  };

  /**
   * @description Opens the Service Appointment for the current form factor.
   *              Phone uses the Field Service Mobile deep link. Desktop and
   *              tablet open a Lightning record view, as a console workspace
   *              tab when the app is a console.
   * @param recordId Service Appointment Id.
   */
  async openAppointmentRecord(recordId) {
    if (this.isDesktopForm) {
      await this.openAppointmentOnDesktop(recordId);
      return;
    }
    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: {
        url: `com.salesforce.fieldservice://v1/sObject/${recordId}/details`
      }
    });
  }

  /**
   * @description Opens the appointment as a console tab when possible,
   *              otherwise as a Lightning record page in the current app.
   * @param recordId Service Appointment Id.
   */
  async openAppointmentOnDesktop(recordId) {
    if (this.isConsoleNavigation) {
      try {
        await openTab({
          recordId,
          focus: true
        });
        return;
      } catch {
        this.navigateToAppointmentPage(recordId);
        return;
      }
    }
    this.navigateToAppointmentPage(recordId);
  }

  /**
   * @description Opens the appointment as a Lightning record page.
   * @param recordId Service Appointment Id.
   */
  navigateToAppointmentPage(recordId) {
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId,
        objectApiName: "ServiceAppointment",
        actionName: "view"
      }
    });
  }

  routeToMarkerLocation = (ind) => {
    const index = ind ?? this.currentMarkerInd;
    this.log("directions", this.filteredMarkers[index]?.value?.id);
    if (!this.filteredMarkers[index]) {
      return;
    }
    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: { url: this.filteredMarkers[index].value.routeUrl }
    });
  };

  selfScheduleAppointment = async (ind) => {
    const index = ind ?? this.currentMarkerInd;
    const marker = this.filteredMarkers[index];
    if (!marker?.value?.id) {
      this.handleError({ message: "Select an appointment to self-schedule." });
      return;
    }
    if (!this.resourceId) {
      this.handleError({
        message: "Service Resource is required to self-schedule."
      });
      return;
    }
    const durationMinutes = Number(marker.value.durationInMinutes) || 60;
    const confirmed = await ConfirmModal.open({
      size: "small",
      header: "Self Schedule?",
      content: `${marker.value.titleFieldValue}: ${marker.value.firstDetailFieldValue}. ${marker.value.distance} away. Start now and finish in ${durationMinutes} minutes?`,
      okButtonText: "Yes",
      cancelButtonText: "No"
    });
    if (!confirmed) {
      this.log("selfSchedule cancelled");
      return;
    }
    this.log("selfSchedule", {
      appointmentId: marker.value.id,
      resourceId: this.resourceId
    });
    try {
      await selfSchedule({
        appointmentId: marker.value.id,
        resourceId: this.resourceId
      });
      this.claimedAppointmentIds.add(marker.value.id);
      await this.refreshMarkers();
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Self Scheduling",
          message: "Appointment scheduled and dispatched.",
          variant: "success"
        })
      );
    } catch (error) {
      this.log("selfSchedule failed", this.toErrorMessage(error));
      this.recordError("selfSchedule", error, {
        appointmentId: marker.value.id,
        resourceId: this.resourceId
      });
      if (this.settings.debugEnabled) {
        this.listErrorsVisible = true;
      }
      this.handleError(error);
    }
  };

  handleTap(event) {
    if (!this.settings.debugEnabled) {
      return;
    }
    if (
      event.target.closest(
        "c-fs-self-schedule-debug, lightning-input, lightning-button, lightning-record-picker, button"
      )
    ) {
      return;
    }
    const now = Date.now();
    this.tapTimes = this.tapTimes.filter((time) => now - time < 2000);
    this.tapTimes.push(now);
    if (this.tapTimes.length >= 5) {
      this.tapTimes = [];
      this.debugVisible = !this.debugVisible;
      this.listErrorsVisible = !this.listErrorsVisible;
    }
  }

  toggleDebugPanel(event) {
    event.stopPropagation();
    this.debugVisible = !this.debugVisible;
  }

  handleDebugInput(event) {
    const field = event.detail.field;
    if (field === "resourceId") {
      this.debugResourceId = event.detail.value;
    } else if (field === "latitude") {
      this.debugLatitude = event.detail.value;
    } else if (field === "longitude") {
      this.debugLongitude = event.detail.value;
    }
  }

  handleDebugApply() {
    this.log("debug apply", {
      resourceId: this.debugResourceId,
      latitude: this.debugLatitude,
      longitude: this.debugLongitude
    });
    if (this.debugLatitude && this.debugLongitude) {
      this.resourceLocation = {
        lat: String(this.debugLatitude).trim(),
        lng: String(this.debugLongitude).trim()
      };
      this.locationSource = "debug";
      this.syncMapOrigin();
    }
    if (this.debugResourceId) {
      this.debugAppliedResourceId = this.debugResourceId;
      this.loadResourceContext();
    }
    this.refreshDiagnostics();
    this.refreshMarkers();
  }

  handleDebugHide() {
    this.debugVisible = false;
  }

  refreshDiagnostics(returnedCount, renderedCount) {
    this.diagnosticRows = [
      { key: "d1", label: "Origin source", value: this.locationSource },
      { key: "d2", label: "Latitude", value: this.resourceLocation.lat },
      { key: "d3", label: "Longitude", value: this.resourceLocation.lng },
      { key: "d4", label: "Search radius", value: this.radiusLabel },
      {
        key: "d5",
        label: "Max results",
        value: String(this.settings.maxResults)
      },
      {
        key: "d6",
        label: "Status filters",
        value: (this.settings.statusValues || []).join(", ") || "(none)"
      },
      {
        key: "d7",
        label: "Service Resource Id",
        value: String(this.resourceId || "(none)")
      },
      { key: "d8", label: "navigator.onLine", value: String(navigator.onLine) },
      { key: "d9", label: "Form factor", value: this.formFactor },
      {
        key: "d10",
        label: "Apex returned",
        value: returnedCount == null ? "(pending)" : String(returnedCount)
      },
      {
        key: "d11",
        label: "Rendered markers",
        value:
          renderedCount == null
            ? String(this.filteredMarkers.length)
            : String(renderedCount)
      },
      {
        key: "d12",
        label: "Bind radius",
        value: this.lastBindRadius || "(none)"
      },
      {
        key: "d13",
        label: "Bind row limit",
        value: this.lastBindRowLimit || "(none)"
      },
      {
        key: "d14",
        label: "Bind statuses",
        value: this.lastBindStatuses || "(none)"
      },
      {
        key: "d15",
        label: "Boolean clause",
        value: this.lastBooleanClause || "(none)"
      },
      {
        key: "d16",
        label: "Overlapping locations",
        value: String(this.overlappingLocationCount)
      },
      {
        key: "d17",
        label: "Matched resource Id",
        value: this.lastMatchedResourceId || "(none)"
      },
      {
        key: "d18",
        label: "Policy matching applied",
        value: this.lastPolicyMatchingApplied || "(pending)"
      },
      {
        key: "d19",
        label: "Radius row count",
        value: this.lastRadiusRowCount || "(pending)"
      },
      {
        key: "d20",
        label: "Skipped territory",
        value: this.lastSkippedTerritoryCount || "(pending)"
      },
      {
        key: "d21",
        label: "Skipped skill",
        value: this.lastSkippedSkillCount || "(pending)"
      },
      {
        key: "d22",
        label: "Policy rule types",
        value: this.lastPolicyRuleTypes || "(none)"
      },
      {
        key: "d23",
        label: "Unimplemented rules",
        value: this.lastUnimplementedRuleTypes || "(none)"
      }
    ];
  }

  log(step, detail) {
    const stamp = new Date().toISOString().substring(11, 23);
    let text = String(detail ?? "");
    if (detail && typeof detail === "object") {
      try {
        text = JSON.stringify(detail);
      } catch {
        text = String(detail);
      }
    }
    const row = {
      key: "t-" + this.executionTrace.length,
      text: stamp + "  " + step + (text ? " → " + text : "")
    };
    this.executionTrace = [...this.executionTrace, row];
  }

  recordError(source, error, context) {
    const appointmentId = context?.appointmentId
      ? String(context.appointmentId)
      : "";
    const resourceId = context?.resourceId ? String(context.resourceId) : "";
    const detailParts = [];
    if (appointmentId) {
      detailParts.push("Appointment " + appointmentId);
    }
    if (resourceId) {
      detailParts.push("Resource " + resourceId);
    }
    this.diagnosticErrors = [
      ...this.diagnosticErrors,
      {
        key: "e-" + this.diagnosticErrors.length,
        source,
        message: this.toErrorMessage(error),
        appointmentId,
        resourceId,
        detail: detailParts.join(" · ")
      }
    ];
  }

  toErrorMessage(error) {
    return (
      error?.body?.message ||
      error?.message ||
      (Array.isArray(error) ? error[0]?.message : null) ||
      String(error || "Unknown error")
    );
  }

  isIos = () => {
    const isIpad =
      navigator.userAgent.includes("Macintosh") &&
      navigator.maxTouchPoints &&
      navigator.maxTouchPoints > 1;
    const isIphone = navigator.platform.includes("iPhone");
    return isIpad || isIphone;
  };

  applyLocationStacks(markers) {
    const groups = new Map();
    (markers || []).forEach((marker, index) => {
      const key = this.locationKey(
        marker.location?.Latitude,
        marker.location?.Longitude
      );
      if (!groups.has(key)) {
        groups.set(key, []);
      }
      groups.get(key).push(index);
    });
    let overlapping = 0;
    groups.forEach((indexes) => {
      if (indexes.length > 1) {
        overlapping += 1;
      }
      indexes.forEach((markerIndex, stackIndex) => {
        const marker = markers[markerIndex];
        const color = marker.value?.color || "#0176d3";
        marker.value = {
          ...marker.value,
          locationKey: this.locationKey(
            marker.location?.Latitude,
            marker.location?.Longitude
          ),
          stackCount: indexes.length,
          stackIndex,
          stackIndexes: indexes
        };
        if (indexes.length > 1) {
          marker.mapIcon = this.getStackedMarkerSVG(color, indexes.length);
        }
      });
    });
    this.overlappingLocationCount = overlapping;
  }

  locationKey(latitude, longitude) {
    const lat = Number(latitude);
    const lng = Number(longitude);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      return "";
    }
    return `${lat.toFixed(5)},${lng.toFixed(5)}`;
  }

  getMarkerSVG(color) {
    const icon = `<?xml version="1.0"?><svg width="32" height="37" viewBox="0 0 32 37" fill="none" xmlns="http://www.w3.org/2000/svg"><path fill-rule="evenodd" d="M19.6725 31.5765C26.739 29.9169 32 23.5728 32 16C32 7.16344 24.8366 0 16 0C7.16344 0 0 7.16344 0 16C0 23.6059 5.30716 29.9723 12.4203 31.598L16.1226 36.4212L19.6725 31.5765Z" fill="${color}"/></svg>`;
    return "data:image/svg+xml;charset=UTF-8," + encodeURIComponent(icon);
  }

  getStackedMarkerSVG(color, count) {
    const label = count > 9 ? "9+" : String(count);
    const icon = `<?xml version="1.0"?><svg width="36" height="41" viewBox="0 0 36 41" fill="none" xmlns="http://www.w3.org/2000/svg"><path fill-rule="evenodd" d="M21.6725 35.5765C28.739 33.9169 34 27.5728 34 20C34 11.1634 26.8366 4 18 4C9.16344 4 2 11.1634 2 20C2 27.6059 7.30716 33.9723 14.4203 35.598L18.1226 40.4212L21.6725 35.5765Z" fill="${color}"/><circle cx="26" cy="10" r="9" fill="#032d60"/><circle cx="26" cy="10" r="8" fill="#ffffff"/><text x="26" y="14" text-anchor="middle" font-size="11" font-family="Arial" font-weight="700" fill="#032d60">${label}</text></svg>`;
    return "data:image/svg+xml;charset=UTF-8," + encodeURIComponent(icon);
  }

  handleError(error) {
    this.dispatchEvent(
      new ShowToastEvent({
        title: "Self Scheduling",
        message: this.toErrorMessage(error),
        variant: "error"
      })
    );
  }
}
