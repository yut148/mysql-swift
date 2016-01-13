//
//  Database.swift
//  MySQL
//
//  Created by ito on 2015/10/24.
//  Copyright © 2015年 Yusuke Ito. All rights reserved.
//

import CMySQL
import CoreFoundation

struct MySQLUtil {
    static func getMySQLErrorString(mysql: UnsafeMutablePointer<MYSQL>) -> String {
        let ch = mysql_error(mysql)
        if ch == nil {
            return "generic error"
        }
        guard let str = String.fromCString(ch) else {
            return "generic error"
        }
        return str as String
    }
}


public protocol ConnectionOption {
    var host: String { get }
    var port: Int { get }
    var user: String { get }
    var password: String { get }
    var database: String { get }
    var timeZone: Connection.TimeZone { get }
    var encoding: Connection.Encoding { get }
    var timeout: Int { get }
    var reconnect: Bool { get }
}

public extension ConnectionOption {
    // Provide default options
    var timeZone: Connection.TimeZone {
        return Connection.TimeZone(GMTOffset: 0)
    }
    var encoding: Connection.Encoding {
        return .UTF8
    }
    var timeout: Int {
        return 10
    }
    var reconnect: Bool {
        return false
    }
}

extension Connection {
    
    public final class TimeZone: Equatable, Hashable {
        let timeZone: CFTimeZoneRef
        public init(name: String) {
            self.timeZone = CFTimeZoneCreateWithName(nil, unsafeBitCast(name as NSString, CFStringRef.self), true)
        }
        public init(GMTOffset: Int) {
            self.timeZone = CFTimeZoneCreateWithTimeIntervalFromGMT(nil, Double(GMTOffset))
        }
        public var hashValue: Int {
            return Int(bitPattern: CFHash(timeZone))
        }
    }
    
    public enum Encoding: String {
        case UTF8 = "utf8"
        case UTF8MB4 = "utf8mb4"
    }
    
}

public func ==(lhs: Connection.TimeZone, rhs: Connection.TimeZone) -> Bool {
    return CFEqual(lhs.timeZone, rhs.timeZone) ||
    CFTimeZoneGetSecondsFromGMT(lhs.timeZone, 0) == CFTimeZoneGetSecondsFromGMT(rhs.timeZone, 0) ||
        CFStringCompare(CFTimeZoneGetName(lhs.timeZone), CFTimeZoneGetName(rhs.timeZone), []) == .CompareEqualTo
}

extension Connection {
    public enum Error: ErrorType {
        case GenericError(String)
        case ConnectionError(String)
        case ConnectionPoolGetConnectionError
    }
}

public final class Connection {
    
    var isInTransaction: Int = 0
    var isInUse: Bool = false
    var mysql_: UnsafeMutablePointer<MYSQL>
    
    let pool: ConnectionPool
    public let options: ConnectionOption
    
    init(options: ConnectionOption, pool: ConnectionPool) {
        self.options = options
        self.pool = pool
        self.mysql_ = nil
    }
    
    public func release() {
        pool.releaseConnection(self)
    }
    
    func connect() throws {
        dispose()
        
        let mysql = mysql_init(nil)
        
        let timeoutPtr = UnsafeMutablePointer<Int>.alloc(1)
        timeoutPtr.memory = options.timeout
        defer {
            timeoutPtr.dealloc(1)
        }
        mysql_options(mysql, MYSQL_OPT_CONNECT_TIMEOUT, timeoutPtr)
        
        let reconnectPtr = UnsafeMutablePointer<my_bool>.alloc(1)
        reconnectPtr.memory = options.reconnect == false ? 0 : 1
        defer {
            reconnectPtr.dealloc(1)
        }
        
        if mysql_real_connect(mysql,
            options.host,
            options.user,
            options.password,
            options.database,
            UInt32(options.port), nil, 0) == nil {
            // error
                throw Error.ConnectionError(MySQLUtil.getMySQLErrorString(mysql))
        }
        mysql_set_character_set(mysql, options.encoding.rawValue)
        self.mysql_ = mysql
    }
    
    func connectIfNeeded() throws -> UnsafeMutablePointer<MYSQL> {
        if isConnected == true {
            return mysql_
        }
        if isConnected == true && ping == true {
            return mysql_
        }
        try connect()
        return mysql_
    }
    
    var mysql: UnsafeMutablePointer<MYSQL>? {
        guard mysql_ != nil else {
            return nil
        }
        return mysql_
    }
    
    var isConnected: Bool {
        guard let mysql = mysql else {
            return false
        }
        return mysql_stat(mysql) != nil ? true : false
    }
    
    var ping: Bool {
        guard let mysql = mysql else {
            return false
        }
        return mysql_ping(mysql) == 0
    }
    
    func dispose() {
        guard let mysql = mysql else {
            return
        }
        mysql_close(mysql)
        self.mysql_ = nil
    }
    
    deinit {
        dispose()
    }
}

