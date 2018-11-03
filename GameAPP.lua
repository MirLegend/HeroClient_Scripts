local ed = ed
local c = require "ZiYuServer"
local cb = pb_loader("cb")()
local cl = pb_loader("cl")()
local hellocb = cl.HelloCB

GameApp = GameApp or {}
ed.GameApp =GameApp

local serverIp = "127.0.0.1"
local serverPort = 20018

local serverBaseIp = "127.0.0.1"
local serverBasePort = 20018

local g_accountName = ""
local g_password = ""

local curserver = 1 --login

local bConnected = false --是否连接到服务器

local tryConnectCounts = 0  --重连次数

local pingTimerId = nil  --服务器心跳定时器

--注册pb文件
function GameApp.InitPb()
	local pbFilePath = "./data/cl.pb"
    print("InitPb file path: "..pbFilePath)
    
    local buffer = read_protobuf_file_c(pbFilePath)
    protobuf.register(buffer) --注:protobuf 是因为在protobuf.lua里面使用module(protobuf)来修改全局名字

	local pbbaseFilePath = "./data/cb.pb"
    print("InitPb file path: "..pbbaseFilePath)
    
    buffer = read_protobuf_file_c(pbbaseFilePath)
    protobuf.register(buffer) --注:protobuf 是因为在protobuf.lua里面使用module(protobuf)来修改全局名字
end

function GameApp.loginServer(account, pwd)
	g_accountName = account
	g_password = pwd
	curserver = 1
	ed.loadBegin()
	GameApp.connectServer(ed.loginip, ed.loginport)
end

function GameApp.reConnectServer()
	local ret, err = c.ziyu_connect(serverIp, serverPort)
	ed.Debug_Msg("reConnectServer ip:"..serverIp)
	if not ret then
		ed.Debug_Msg("reConnectServer error!!  can not connect to "..serverIp.." port:"..serverPort)
		return
	end
end

function GameApp.connectServer(ip, port)
	serverIp = ip
	serverPort = port
	local ret, err = c.ziyu_connect(ip, port)
	ed.Debug_Msg("connectServer ip:"..ip)
	if not ret then
		ed.Debug_Msg("connect error!!  can not connect to "..serverIp.." port:"..serverPort)
		return
	end
end

local clientversion = 51

function GameApp.Hello()
	local msg = cl.Hello()
	msg.version = clientversion
	msg.extraData = "helloziyu"
	local code, err = msg:Serialize()

	GameApp.SendMsg(90, 1, code)
end

function GameApp.SendMsg(maincmd, subcmd, msg)
	ed.Debug_Msg("[GameApp.lua|SendMsg] GameApp.SendMsg: " .. maincmd..""..subcmd)
	c.ziyu_send(maincmd, subcmd, msg)
end

function GameApp.HelloBase()

	local msg = cb.Hello()
	msg.version = clientversion
	msg.extraData = "helloziyu"
	local code, err = msg:Serialize()

	GameApp.SendMsg(91, 1, code)
	
end

function GameApp.Login(loginName, password)
	local msg = cl.Login()
	msg.ctype = 1
	msg.account = loginName
	msg.password = password
	msg.extraData = "helloziyu"
	local code, err = msg:Serialize()

	GameApp.SendMsg(90, 5, code)
	
end

function GameApp.LoginBase(loginName, password)

	local msg = cb.Login()
	msg.account = loginName
	msg.password = password
	local code, err = msg:Serialize()

	GameApp.SendMsg(91, 3, code)
end

--有待优化 存入registry中
function onConnected()
	ed.Debug_Msg("lua =============  onConnected curser: "..curserver)
	bConnected = true
	tryConnectCounts = 0
	ed.loadEnd()
	--连接后 第一步是hello下
	if curserver == 1 then
		GameApp.Hello()
	elseif curserver == 2 then
		GameApp.HelloBase()
	end
end

--有待优化 存入registry中
function onConnectedFail()
	ed.Debug_Msg("lua =============  onConnectedFail")
	bConnected = false
	if tryConnectCounts > 5 then
		
		tryConnectCounts = 0
		print("ConnectedFail ---------------------- ")
		FireEvent("SendMsgFail")
	else
		tryConnectCounts =tryConnectCounts + 1
		FireEvent("ConnectedFail")
    end
end

--有待优化 存入registry中
function onConnectedClosed()
	ed.Debug_Msg("lua =============  onConnectedClosed")
	bConnected = false
	if pingTimerId then
		CCDirector:sharedDirector():getScheduler():unscheduleScriptEntry(pingTimerId)
		pingTimerId = nil
	end
end

function GameApp.RecvNetMessage()
	c.ziyu_update()
end

function doPingPong()
	if not connection then
		return
	end

	local nowTime = ed.getSystemTime()
	LegendLog("[network.lua|doPingProxy]  doPingProxy : " .. nowTime)
	local passTime = nowTime - lastHeartBeatTime
	if (passTime >= lostConnectInterval) then
		close()
		return
	end

	nowTime = nowTime * 1000
	sz = XPACKET_SendPing:_Size(nowTime);
	buf = string.rep("a", sz);
	ret = XPACKET_SendPing:_ToBuffer(buf, sz, nowTime);
	--LegendLog(print_bytes(buf))

	local r1, r2 = ziyu.send(myip, myport, buf)--connection:send(buf)
	if not r1 then
		ed.showToast(T(LSTR("NETWORK.SENDING_FAILED_PLEASE_CHECK_THE_NETWORK_SETTING")))
		close()
	end
end

--有待优化 存入registry中
function onNetMessage(mainCmd, subCmd, buffer)
	ed.Debug_Msg("onNetMessage ============================================= cmd:"..mainCmd.." subCmd:"..subCmd)
	
	if mainCmd == 90 then --login cmd
		if subCmd == 2 then
			--local result = protobuf.decode("client_loginserver.HelloCB", buffer)
			local msg, err = hellocb():Parse(buffer)
			if not msg then
				ed.LegendLog("[netword.lua|recv] ERROR | Decode message failed | " .. err)
				return
			end
			ed.Debug_Msg("HelloCB result: "..msg.result)
			ed.Debug_Msg("HelloCB version: "..msg.version)
			ed.Debug_Msg("HelloCB extraData: "..msg.extraData)
			GameApp.Login(g_accountName, g_password)
		elseif subCmd == 6 then
			--local result = protobuf.decode("client_loginserver.LoginFailed", buffer)
			local result, err = cl.LoginFailed():Parse(buffer)
			ed.Debug_Msg("LoginFailed failedcode: "..result.failedcode.." datas:"..result.extraData)
		elseif subCmd == 7 then
			--local result = protobuf.decode("client_loginserver.LoginSuccessfully", buffer)
			local result, err = cl.LoginSuccessfully():Parse(buffer)
			ed.Debug_Msg("LoginSuccessfully ip: "..result.baseIp)
			ed.Debug_Msg("LoginSuccessfully port: "..result.basePort)
			serverBaseIp = result.baseIp
			serverBasePort = result.basePort
			--连接到base
			curserver = 2
			GameApp.connectServer(serverBaseIp, serverBasePort)
		end
	elseif mainCmd == 91 then --base cmd
		if subCmd == 2 then
			--local result = protobuf.decode("client_baseserver.HelloCB", buffer)
			local result, err = cb.HelloCB():Parse(buffer)
			ed.Debug_Msg("HelloCB base result: "..result.result)
			ed.Debug_Msg("HelloCB base version: "..result.version)
			ed.Debug_Msg("HelloCB base extraData: "..result.extraData)
			--ed.dump(result)
			GameApp.LoginBase(g_accountName, g_password)
		elseif subCmd == 4 then  --登陆失败
			--local result = protobuf.decode("client_baseserver.LoginBaseappFailed", buffer)
			local result, err = cb.LoginBaseappFailed():Parse(buffer)
			ed.Debug_Msg("LoginBaseappFailed failedcode: "..result.retCode)
		elseif subCmd == 5 then  --登陆成功 创建proxy
			--local result = protobuf.decode("client_baseserver.CreatedProxies", buffer)
			local result, err = cb.CreatedProxies():Parse(buffer)
			--ed.dump(result)
			ed.Debug_Msg("CreatedProxies entityid: "..result.entityID)
			if not pingTimerId then
				pingTimerId = CCDirector:sharedDirector():getScheduler():scheduleScriptFunc(doPingPong, 60, false)
			end
		elseif subCmd == 6 then  --登陆成功 创建proxy
			--local result = decodeAll("client_baseserver.down_msg", buffer)
			--ed.dump(result)
			ed.Debug_Msg("down_msg -----------------------------------")
			ed.dispatch(buffer)
		end
	end
	
	
end

--return GameApp
