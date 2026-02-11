const fs = require('fs');
const path = 'interface.js';
let content = fs.readFileSync(path, 'utf8');

// 1. Destructure
content = content.replace(
  'const { battery_state, daemon_state, maintain_percentage=80, percentage } = await get_battery_status()',
  'const { battery_state, daemon_state, maintain_percentage=80, percentage, cycle_count, battery_health } = await get_battery_status()'
);

// 2. Insert menu items
const target = `            {
                label: `Power: ${ daemon_state }`,
                enabled: false
            },`;

const injection = `
            {
                label: `Health: ${ battery_health || 'unknown' }%`,
                enabled: false
            },
            {
                label: `Cycle count: ${ cycle_count || 'unknown' }`,
                enabled: false
            },`;

if (!content.includes('label: `Health:')) {
    content = content.replace(target, target + injection);
    fs.writeFileSync(path, content);
    console.log('Injected menu items successfully');
} else {
    console.log('Menu items already present');
}
