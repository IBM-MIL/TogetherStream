//
//  AccountDataManager.swift
//  Stormtrooper
//
//  Created by Daniel Firsht on 12/5/16.
//  Copyright © 2016 IBM. All rights reserved.
//

import Foundation
import FBSDKLoginKit

class AccountDataManager {
	static let sharedInstance = AccountDataManager()
	
	// TODO: move to plist
	private var serverAddress = "https://stormtrooper.mybluemix.net"
	private var urlSession = URLSession.shared
	private var _serverAccessToken: String?
	private var serverAccessToken: String? {
		get {
			return _serverAccessToken
		}
		set {
			let userDefaults = UserDefaults()
			userDefaults.set(newValue, forKey: "server_access_token")
			userDefaults.synchronize()
			_serverAccessToken = newValue
		}
	}
	
	func sendInvite(forStream stream: String, to users: [User]) {
		guard let serverAccessToken = serverAccessToken, let url = URL(string: serverAddress + "/invites?access_token=" + serverAccessToken) else {
			return
		}
		let host = FacebookDataManager.sharedInstance.profile?.name ?? ""
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.addValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try? JSONSerialization.data(withJSONObject: ["host": host, "stream": stream, "users": users.map({$0.id})])
		sendToServer(request: request){_,_,_ in}
	}
	
	func signup(withFacebookAccessToken accessToken: String) {
		guard let url = URL(string: serverAddress + "/auth/facebook/token/login") else {
			return
		}
		var request = URLRequest(url: url)
		request.addValue(accessToken, forHTTPHeaderField: "access_token")
		let task = urlSession.dataTask(with: request) {data,response,error in
			if let url = response?.url {
				let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
				let token = queryItems?.first(where: {$0.name == "access_token"})
				self.serverAccessToken = token?.value
				self.postDeviceTokenToServer()
			}
		}
		task.resume()
	}
	
	private init() {
		_serverAccessToken = UserDefaults().string(forKey: "server_access_token")
	}
	
	private func postDeviceTokenToServer() {
		guard let serverAccessToken = serverAccessToken, let deviceToken = UserDefaults.standard.object(forKey: "deviceToken") as? String, let url = URL(string: serverAddress + "/invites/device-token?access_token=" + serverAccessToken) else {
			return
		}
		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.addValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try? JSONSerialization.data(withJSONObject: ["token": deviceToken])
		sendToServer(request: request){_,_,_ in}
		
	}
	
	private func sendToServer(request: URLRequest, withCallback callback: @escaping (Data?, URLResponse?, Error?) -> Void) {
		let task = urlSession.dataTask(with: request) {data,response,error in
			guard let httpResponse = response as? HTTPURLResponse else {
				// Not HTTP Request, just pass through
				callback(data, response, error)
				return
			}
			if httpResponse.statusCode == 401 {
				//attempt to refresh token
				self.refreshToken() {error in
					if error != nil {
						callback(nil, nil, error)
					}
					else {
						self.sendToServer(request: request, withCallback: callback)
					}
				}
			}
			else {
				callback(data, response, error)
			}
		}
		task.resume()
	}
	
	private func refreshToken(withCallback callback: @escaping (Error?) -> Void) {
		guard let serverAccessToken = serverAccessToken, let url = URL(string: serverAddress + "/auth/refresh?access_token=" + serverAccessToken) else {
			callback(ServerError.cannotFormURL)
			return
		}
		let task = urlSession.dataTask(with: url) {data, response, error in
			guard let data = data, error != nil else {
				callback(error)
				return
			}
			let jsonData = try? JSONSerialization.jsonObject(with: data)
			if let newServerAccessToken = (jsonData as? [String: String])?["access_token"] {
				self.serverAccessToken = newServerAccessToken
				callback(nil)
			}
			else {
				callback(ServerError.unexpectedResponse)
			}
		}
		task.resume()
	}
}
