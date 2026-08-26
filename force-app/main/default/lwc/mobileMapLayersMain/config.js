export const config = {
  mapObjects: [
    {
      value: "ServiceAppointment",
      label: "Service Appointment",
      plural: "Service Appointments",
      latField: "Latitude",
      longField: "Longitude",
      titleField: "AppointmentNumber",
      firstDetailField: "Subject",
      secondDetailField: "Status",
      thirdDetailField: "DurationInMinutes"
    }
  ],
  distanceUnit: "km",
  searchRadius: 10
};
