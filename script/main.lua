PROJECT = "air780e_forwarder"
VERSION = "1.0.0"

log.setLevel("DEBUG")
log.info("main", PROJECT, VERSION)

sys = require "sys"
sysplus = require "sysplus"
require "sysplus"

-- 添加硬狗防止程序卡死, 在支持的设备上启用这个功能
if wdt then
    -- 初始化 watchdog 设置为 9s
    wdt.init(9000)
    -- 3s 喂一次狗
    sys.timerLoopStart(wdt.feed, 3000)
end

-- 设置 DNS
socket.setDNS(nil, 1, "119.29.29.29")
socket.setDNS(nil, 2, "223.5.5.5")

-- 设置 SIM 自动恢复, 搜索小区信息间隔, 最大搜索时间
mobile.setAuto(1000 * 10, 1000 * 60, 1000 * 5)

-- POWERKEY
local button_last_press_time, button_last_release_time = 0, 0
gpio.setup(
    35,
    function()
        local current_time = mcu.ticks()
        -- 按下
        if gpio.get(35) == 0 then
            button_last_press_time = current_time -- 记录最后一次按下时间
            return
        end
        -- 释放
        if button_last_press_time == 0 then -- 开机前已经按下, 开机后释放
            return
        end
        if current_time - button_last_release_time < 250 then -- 防止连按
            return
        end
        local duration = current_time - button_last_press_time -- 按键持续时间
        button_last_release_time = current_time -- 记录最后一次释放时间
        if duration > 2000 then
            log.debug("EVENT.POWERKEY_LONG_PRESS", duration)
            sys.publish("POWERKEY_LONG_PRESS", duration)
        elseif duration > 50 then
            log.debug("EVENT.POWERKEY_SHORT_PRESS", duration)
            sys.publish("POWERKEY_SHORT_PRESS", duration)
        end
    end,
    gpio.PULLUP
)

config = require "config"
util_netled = require "util_netled"
util_mobile = require "util_mobile"
util_location = require "util_location"
util_notify = require "util_notify"

-- 短信回调
sms.setNewSmsCb(
    function(num, txt, metas)
        log.info("smsCallback", num, txt, metas and json.encode(metas) or "")
        util_netled.blink(50, 50, 5000)
        util_notify.send({txt, "", "发件人号码: " .. num, "#SMS"})
    end
)

sys.taskInit(
    function()
        -- 等待网络环境准备就绪
        sys.waitUntil("IP_READY")

        util_netled.blink(50, 50, 1000)

        -- 开机基站定位
        util_location.getCoord(
            function()
                log.info("publish", "COORD_INIT_DONE")
                sys.publish("COORD_INIT_DONE")
            end
        )
        sys.waitUntil("COORD_INIT_DONE", 1000 * 20)

        -- 开机通知
        if config.BOOT_NOTIFY then
            util_notify.send("#BOOT")
        end

        -- 定时查询流量
        if config.QUERY_TRAFFIC_INTERVAL and config.QUERY_TRAFFIC_INTERVAL >= 1000 * 60 then
            sys.timerLoopStart(util_mobile.queryTraffic, config.QUERY_TRAFFIC_INTERVAL)
        end

        -- 定时基站定位
        if config.LOCATION_INTERVAL and config.LOCATION_INTERVAL >= 1000 * 10 then
            sys.timerLoopStart(util_location.getCoord, config.LOCATION_INTERVAL)
        end

        -- 电源键短按发送测试通知
        sys.subscribe(
            "POWERKEY_SHORT_PRESS",
            function()
                util_notify.send("#ALIVE")
            end
        )
        -- 电源键长按查询流量
        sys.subscribe("POWERKEY_LONG_PRESS", util_mobile.queryTraffic)
    end
)

sys.run()
