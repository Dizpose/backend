import ballerina/http;
import ballerina/io;
import ballerina/jwt;
import ballerina/time;
import ballerinax/mongodb;

configurable string host = ?;
configurable int port = ?;

configurable string username = ?;
configurable string password = ?;
configurable string database = ?;

public enum RequestStatus {
    PENDING,
    SCHEDULED,
    COMPLETED
}

public enum WasteType {
    ELECTRONICS,
    FURNITURE,
    PLASTIC,
    METAL,
    ORGANIC
}

public enum Size {
    SMALL,
    MEDIUM,
    LARGE
}

type PickupRequest record {
    string mongoId?;
    string id?;
    WasteType wasteType;
    string description?;
    Size size;
    string requestedDate;
    string serviceProviderId?;
    string scheduledDate?;
    string userId?;
    RequestStatus status?;
    decimal[] location;
};

type userInput record {
    string[] wasteType;
    decimal[] location;
    decimal radius;
};

final mongodb:Client mongoDb = check new ({
    connection: {
        serverAddress: {
            host,
            port
        },
        auth: <mongodb:ScramSha256AuthCredential>{
            username,
            password,
            database
        }
    }
});

@http:ServiceConfig {
    cors: {
        allowOrigins: ["http://localhost:8081"],
        allowMethods: ["GET", "POST", "OPTIONS", "PUT", "DELETE", "PATCH"]
    },
    auth: [
        {
            jwtValidatorConfig: {
                issuer: "buddhi",
                audience: "provider-service",
                signatureConfig: {
                    certFile: "resources/public.crt"
                }
            }
        }
    ]
}
service /providerService on new http:Listener(9092) {

    private final mongodb:Database db;

    function init() returns error? {
        self.db = check mongoDb->getDatabase("DizposeDB");
    }

    // Accept a pickup request
    resource function put acceptRequest/[string requestId](http:Caller caller, http:Request req) returns error? {
        string|http:HeaderNotFoundError authHeaderResult = req.getHeader("Authorization");

        if authHeaderResult is string && authHeaderResult.startsWith("Bearer ") {
            string token = authHeaderResult.substring(7);
            string providerId = check decodeToken(token);
            io:println("id", providerId);

            mongodb:Collection pickupRequestsCollection = check self.db->getCollection("PickupRequests");

            // Parse the request body to extract the scheduledDate
            json requestBody = check req.getJsonPayload();
            if requestBody.scheduledDate is string {
                string scheduledDate = check requestBody.scheduledDate;

                map<json> filter = {
                    "id": requestId,
                    "status": "PENDING"
                };

                mongodb:Update updateData = {
                    "set": {
                        "status": "SCHEDULED",
                        "serviceProviderId": providerId,
                        "scheduledDate": scheduledDate
                    }
                };

                var updateResult = pickupRequestsCollection->updateOne(filter, updateData);

                if updateResult is mongodb:UpdateResult {
                    if updateResult.matchedCount > 0 {
                        check caller->respond("Pickup request accepted and scheduled.");
                    } else {
                        return error("No request found with the specified ID in pending state.");
                    }
                } else if updateResult is mongodb:DatabaseError {
                    return error("Database error: " + updateResult.message());
                } else if updateResult is mongodb:ApplicationError {
                    return error("Application error: " + updateResult.message());
                }
            } else {
                return error("Scheduled date is missing from the request body.");
            }
        } else if authHeaderResult is http:HeaderNotFoundError {
            return error("Authorization header is missing");
        } else {
            return error("Authorization header is invalid");
        }
    }

    // Complete a pickup request
    resource function put completeRequest/[string requestId](http:Caller caller, http:Request req) returns error? {
        string|http:HeaderNotFoundError authHeaderResult = req.getHeader("Authorization");

        if authHeaderResult is string && authHeaderResult.startsWith("Bearer ") {
            string token = authHeaderResult.substring(7);
            string providerId = check decodeToken(token);

            mongodb:Collection pickupRequestsCollection = check self.db->getCollection("PickupRequests");

            map<json> filter = {
                "id": requestId,
                "serviceProviderId": providerId,
                "status": "SCHEDULED"
            };

            mongodb:Update updateData = {
                "set": {
                    "status": "COMPLETED",
                    "completedDate": time:utcToString(time:utcNow())
                }
            };

            var updateResult = pickupRequestsCollection->updateOne(filter, updateData);

            if updateResult is mongodb:UpdateResult {
                if updateResult.matchedCount > 0 {
                    check caller->respond("Pickup request completed.");
                } else {
                    return error("No scheduled request found with the specified ID for this provider.");
                }
            } else if updateResult is mongodb:DatabaseError {
                return error("Database error: " + updateResult.message());
            } else if updateResult is mongodb:ApplicationError {
                return error("Application error: " + updateResult.message());
            }
        } else if authHeaderResult is http:HeaderNotFoundError {
            return error("Authorization header is missing");
        } else {
            return error("Authorization header is invalid");
        }
    }

    // Get pickup requests based on location and service type
    resource function post filterRequests(userInput input, http:Caller caller, http:Request req) returns error? {
        string[] wasteType = input.wasteType;
        io:println("service", wasteType);
        decimal[] location = input.location;
        io:println("location", location);
        decimal radius = input.radius;
        io:println("radius", radius);

        mongodb:Collection pickupRequestsCollection = check self.db->getCollection("PickupRequests");

        // Updated aggregation pipeline with $project stage
        map<json>[] aggregationPipeline = [
            {
                "$geoNear": {
                    "near": location,
                    "distanceField": "dist.calculated",
                    "maxDistance": radius,
                    "query": {
                        "status": "PENDING",
                        "wasteType": {"$in": wasteType}
                    },
                    "spherical": true
                }
            },
            {
                "$project": {
                    "_id": 0,
                    "mongoId": {"$toString": "$_id"},
                    "id": 1,
                    "wasteType": 1,
                    "description": 1,
                    "size": 1,
                    "userId": 1,
                    "status": 1,
                    "location": 1
                }
            }
        ];

        var result = pickupRequestsCollection->aggregate(aggregationPipeline, json);

        if result is stream<json, error?> {
            json[] nearbyRequests = [];

            error? e = result.forEach(function(json request) {
                nearbyRequests.push(request);
            });

            if e is error {
                return error("Error occurred while processing results: " + e.message());
            }

            check result.close();
            check caller->respond(nearbyRequests);
        } else if result is mongodb:DatabaseError {
            return error("Database error: " + result.message());
        } else if result is mongodb:ApplicationError {
            return error("Application error: " + result.message());
        } else {
            return error("Unexpected error occurred while fetching data");
        }
    }

}
isolated function decodeToken(string token) returns string|error {
    [jwt:Header, jwt:Payload] result = check jwt:decode(token);
    return result[1]["sub"].toString();
};