const test = require('node:test')
const assert = require('node:assert/strict')
const { parseStatus } = require('../app/modules/status')
const base = { schema:1, backend:'firmware', target:60, percentage:60, mode:'enabled', applied:'verified', power:'unknown', force_discharge:false }
test('unknown charging is not converted to disabled', () => {
    const s = parseStatus(JSON.stringify(base))
    assert.equal(s.charging, null)
    assert.match(s.daemon_state, /Power state unknown/)
})
test('input target flows into the GUI without an 80% default', () => {
    for (const target of [1,60,75,96,100]) {
        const s = parseStatus(JSON.stringify({...base,target}))
        assert.equal(s.maintain_percentage,String(target))
    }
    assert.equal(parseStatus(JSON.stringify({...base,target:null,mode:'unset'})).maintain_percentage,undefined)
})
test('applied limit does not imply bypass; verified bypass does', () => {
    assert.doesNotMatch(parseStatus(JSON.stringify(base)).daemon_state,/Bypass verified/)
    assert.match(parseStatus(JSON.stringify({...base,power:'bypass_verified'})).daemon_state,/Bypass verified/)
    assert.equal(parseStatus(JSON.stringify({...base,power:'bypass_verified'})).charging,false)
})
test('stopped policy is not presented as an active limiter', () => {
    const s = parseStatus(JSON.stringify({...base,mode:'stopped'}))
    assert.equal(s.limiter_requested,false)
    assert.equal(s.limiter_applied,false)
})
test('bad targets and unknown schema fail closed', () => {
    for (const change of [{target:'60;echo bad'},{target:101},{schema:2},{power:'disabled'},{percentage:200}])
        assert.throws(() => parseStatus(JSON.stringify({...base,...change})))
})
