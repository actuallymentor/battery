const test = require('node:test')
const assert = require('node:assert/strict')
const vm = require('node:vm')
const fs = require('node:fs')
const path = require('node:path')
const status = require('../app/modules/status')
function load(target=60, failCommand) {
    const commands=[]
    const context={ module:{exports:{}}, process:{env:{}}, require(name) {
        if(name==='electron') return { app:{} }
        if(name==='node:child_process') return { exec(command,options,cb) {
            commands.push(command)
            if(failCommand && command.includes(failCommand)) return cb(Object.assign(new Error('failure'),{code:'ETIMEDOUT'}),'','')
            const out=command.endsWith(' version') ? 'v1.3.5-local-firmware.1' : command.endsWith(' status_json') ? JSON.stringify({schema:1,backend:'firmware',target,percentage:60,mode:'stopped',applied:'verified',power:'unknown',force_discharge:false}) : ''
            cb(null,out,'')
        } }
        if(name==='./helpers') return {log(){},alert:async()=>{},wait:()=>new Promise(()=>{}),confirm:async()=>false}
        if(name==='./settings') return {get_force_discharge_setting:()=>true}
        if(name==='./status') return status
        throw new Error(name)
    } }
    vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../app/modules/battery.js'),'utf8'),context)
    return {api:context.module.exports, commands}
}
test('GUI startup recovers without stopping, killing, or updating the controller', async()=>{
    const {api,commands}=load()
    await api.initialize_battery()
    assert(commands.some(x=>x.endsWith(' maintain recover')))
    assert(!commands.some(x=>/maintain stop|pkill|update_silent|curl/.test(x)))
})
test('GUI enable uses the saved CLI target and policy force flag',async()=>{
    const {api,commands}=load(75)
    await api.enable_battery_limiter()
    assert(commands.some(x=>x.endsWith(' maintain 75')))
    assert(!commands.some(x=>/maintain 80|force-discharge/.test(x)))
})
test('unset target never silently becomes 80',async()=>{
    const {api,commands}=load(null)
    await assert.rejects(api.enable_battery_limiter())
    assert(!commands.some(x=>x.includes(' maintain ')))
})
test('command timeout is an error for both apply and stop',async()=>{
    const {api}=load(60,' maintain ')
    await assert.rejects(api.enable_battery_limiter())
    await assert.rejects(api.disable_battery_limiter())
})
