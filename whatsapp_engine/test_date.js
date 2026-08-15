const dateObj = new Date(2026, 7, 16);
const year = dateObj.getFullYear();
const month = String(dateObj.getMonth() + 1).padStart(2, '0');
const day = String(dateObj.getDate()).padStart(2, '0');

const ymd = `${year}-${month}-${day}`;
const isoDrawDate = `${year}-${month}-${day}T12:00:00.000Z`;

console.log('Target YMD:', ymd);
console.log('Target ISO Draw Date:', isoDrawDate);
