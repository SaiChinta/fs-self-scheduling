export function haversine(lat1, lng1, lat2, lng2, distanceUnit) {
  const deg2rad = (deg) => deg * (Math.PI / 180);
  const radius = distanceUnit === "mi" ? 3958.8 : 6371;
  const dLat = deg2rad(lat2 - lat1);
  const dLng = deg2rad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(deg2rad(lat1)) *
      Math.cos(deg2rad(lat2)) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return radius * c;
}

export function formatDistance(distance, unit) {
  return `${Number(distance).toFixed(2)} ${unit}`;
}
