/**
 * Created by danielfirsht on 11/22/16.
 */

var pg = require('pg');
var appVars = require('../config/appVars');

var userController = {};

userController.registerUser = function(user) {
    return userController.saveUser(user);
};

userController.saveUser = function (user) {
    return new Promise(function (resolve, reject) {
        var client = new pg.Client(appVars.postgres.uri);
        client.connect();
        // Update users if exists, otherwise insert it
        // Warning: this is not safe if executed from multiple sessions at the same time
        client.query("UPDATE users SET id=$1, device_token=$2 WHERE id=$1;", [user.id, user.deviceToken]);
        client.query("INSERT INTO users (id) SELECT $1 WHERE NOT EXISTS (SELECT 1 FROM users WHERE id = $2);",  [user.id, user.id],
            function (err) {
                if (err) reject(err);

                resolve(user);

                client.end();
            }
        );
    });
};

userController.saveExternalAccount = function(userId, externalAccount) {
    return new Promise(function (resolve, reject) {
        var parameters = [externalAccount.id, externalAccount.accessToken.cipher, externalAccount.accessToken.iv, externalAccount.accessToken.tag,
            externalAccount.refreshToken.cipher, externalAccount.refreshToken.iv, externalAccount.refreshToken.tag, userId, externalAccount.provider];
        var client = new pg.Client(appVars.postgres.uri);
        client.connect();
        // Update external account if exists with that provider, otherwise insert it
        // Warning: this is not safe if executed from multiple sessions at the same time
        client.query("UPDATE external_auth SET id=$1, access_token=$2, at_iv=$3, at_tag=$4, refresh_token=$5, rt_iv=$6, rt_tag=$7 WHERE user_id=$8 AND provider=$9;", parameters);
        client.query("INSERT INTO external_auth (id, access_token, at_iv, at_tag, refresh_token, rt_iv, rt_tag, user_id, provider) SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9"
            + "WHERE NOT EXISTS (SELECT 1 FROM external_auth WHERE user_id=$8 AND provider=$9);", parameters,
            function (err) {
                if (err) reject(err);

                resolve();

                client.end();
            }
        );
    });
};

userController.getUserByID = function (id) {
  return new Promise(function (resolve, reject) {
      var client = new pg.Client(appVars.postgres.uri);
      client.connect();
      // Get user info
      client.query("SELECT id, device_token FROM users WHERE id=$1", [id],
          function (err, result) {
              if (err) reject(err);
              if (result.rowCount < 1) {
                  resolve(null);
                  client.end();
              }
              else {
                  var user = {id: result.rows[0].id, deviceToken: result.rows[0].device_token};
                  // Get external accounts
                  client.query("SELECT id, provider, access_token, at_iv, at_tag FROM external_auth WHERE user_id=$1", [id],
                      function (err, result) {
                          if (err) reject(err);
                          user.externalAccounts = result.rows;
                          resolve(user);

                          client.end();
                      });
              }
          }
      );
  })
};

userController.getUserAccountByExternalAccount = function (externalAccount) {
  return new Promise(function (resolve, reject) {
      var client = new pg.Client(appVars.postgres.uri);
      client.connect();
      // Get user info
      client.query("SELECT user_id FROM external_auth WHERE id=$1 AND provider=$2", [externalAccount.id, externalAccount.provider],
          function (err, result) {
              if (err) reject(err);
              if (result.rowCount < 1) {
                  resolve(null);
              }
              else {
                  client.query("SELECT id, device_token FROM users WHERE id=$1", [result.rows[0].user_id],
                      function (err, result) {
                          if (err) reject(err);
                          if (result.rowCount < 1) {
                              resolve(null);
                              client.end();
                          }
                          resolve({id: result.rows[0].id, deviceToken: result.rows[0].device_token});
                          client.end();
                      });
              }
          }
      );
  })
};

userController.processExternalAuthentication = function (req, externalAccount) {
    return new Promise(function (resolve, reject) {
        userController.getUserAccountByExternalAccount(externalAccount)
            .then(function (user) {
                if (user) {
                    // External account is already linked to a user account
                    if (req.user) {
                        // Already logged in
                        if (req.user.id == user.id) {
                            // External already linked to logged in user, just return that
                            resolve(req.user);
                        }
                        else {
                            // uh oh, need to merge accounts
                            mergeIds(user.id, req.user.id);
                        }
                    }
                    else {
                        // return the account that's linked
                        userController.getUserByID(user.id)
                            .then(function (user) {
                                resolve(user);
                            });
                    }
                }
                else {
                    // External account is new
                    if (req.user) {
                        // already logged in, add external account
                        userController.saveExternalAccount(req.user.id, externalAccount)
                            .then(function () {
                                req.user.externalAccounts.push(externalAccount);
                                resolve(req.user);
                            });
                    }
                    else {
                        // create new account
                        generateId().then(function (id) {
                            userController.registerUser({id: id, external_account: null})
                                .then(function (user) {
                                    userController.saveExternalAccount(id, externalAccount)
                                        .then(function () {
                                            user.externalAccounts = [externalAccount];
                                            resolve(user);
                                        })
                                })
                        });
                    }
                }
            }, function (error) {
                reject(error);
            })
    })
};

userController.getOrCreateStream = function (req) {
    var user = req.user;
    var streamPath = req.body["streamPath"];
    var streamName = req.body["streamName"];
    return new Promise(function (resolve, reject) {
        var client = new pg.Client(appVars.postgres.uri);
        client.connect();
        client.query("SELECT * FROM streams WHERE user_id=$1", [user.id],
            function (err, result) {
                if (err) {
                    reject(err);
                    return;
                }
                if (result.rowCount > 0) {
                    resolve(result.rows[0])
                }
                else {
                    client.query("INSERT INTO streams (user_id, csync_path, stream_name) VALUES ($1, $2, $3) RETURNING id", [user.id, streamPath, streamName],
                        function (err, result) {
                            if (err) {
                                reject(err);
                                return;
                            }
                            if (result.rowCount < 1) {
                                reject(null);
                                client.end();
                            }
                            resolve({id: result.rows[0].id, user_id: user.id, csync_path: streamPath, stream_name: streamName});
                            client.end();
                        });
                }
            }
        );
    })
};

function generateId() {
    return new Promise(function (resolve, reject) {
        var generateAttempt = function () {
            var id = "";
            var possible = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

            for( var i = 0; i < 10; i++ ) {
                id += possible.charAt(Math.floor(Math.random() * possible.length));
            }

            userController.getUserByID(id)
                .then(function (user) {
                    if(!user) {
                        resolve(id);
                    }
                    else {
                        generateAttempt();
                    }
                }, function (error) {
                    reject(error);
                })
        };
        generateAttempt();
    });
}

function mergeIds(id1, id2) {
    return new Promise(function (resolve, reject) {
        var client = new pg.Client(appVars.postgres.uri);
        client.connect();
        client.query("UPDATE external_auth SET user_id=$1 WHERE user_id = $2;", [id1, id2]);
        client.query("DELETE FROM users WHERE id=$1;", [id2],
            function (err) {
                if (err) reject(err);

                client.end();
                userController.getUserByID(id1)
                    .then(function (user) {
                        resolve(user);
                    }, function (error) {
                        reject(error);
                    });
            }
        );
    })
}

module.exports = userController;