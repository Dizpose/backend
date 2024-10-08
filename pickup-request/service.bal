import ballerina/http;
import ballerina/io;
import ballerina/jwt;
import ballerina/uuid;
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
    string serviceProviderId?;
    string scheduledDate?;
    string userId?;
    RequestStatus status?;
    decimal[] location;
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
                audience: "user-service",
                signatureConfig: {
                    certFile: "resources/public.crt"
                }
            }
        }
    ]
}

service /pickupRequest on new http:Listener(9091) {

    private final mongodb:Database db;

    function init() returns error? {
        self.db = check mongoDb->getDatabase("DizposeDB");
    }

    // new request
    resource function post newRequest(PickupRequest input, http:Caller caller, http:Request req) returns error? {

        string|http:HeaderNotFoundError authHeaderResult = req.getHeader("Authorization");

        if authHeaderResult is string && authHeaderResult.startsWith("Bearer ") {
            string token = authHeaderResult.substring(7);
            string userId = check decodeToken(token);

            mongodb:Collection pickupRequestsCollection = check self.db->getCollection("PickupRequests");

            string requestId = uuid:createType1AsString();

            PickupRequest newRequest = {
                id: requestId,
                wasteType: input.wasteType,
                description: input.description,
                size: input.size,
                status: PENDING,
                userId: userId,
                location: input.location
            };

            check pickupRequestsCollection->insertOne(newRequest);

            check caller->respond("Pickup request created with ID: " + requestId);
            return;
        } else if authHeaderResult is http:HeaderNotFoundError {
            return error("Authorization header is missing");
        } else {
            return error("Authorization header is invalid");
        }
    }

    //get one request
    resource function get request/[string requestId](http:Caller caller, http:Request req) returns error? {
        // Get the Authorization header
        string|http:HeaderNotFoundError authHeaderResult = req.getHeader("Authorization");

        if authHeaderResult is string && authHeaderResult.startsWith("Bearer ") {
            string token = authHeaderResult.substring(7);
            string userId = check decodeToken(token);

            mongodb:Collection pickupRequestsCollection = check self.db->getCollection("PickupRequests");

            map<json> filter = {
                "userId": userId,
                "id": requestId
            };

            var result = pickupRequestsCollection->findOne(filter,{}, {}, PickupRequest);

            if result is PickupRequest {
                check caller->respond(result);
            } else if result is mongodb:DatabaseError {
                return error("Database error: " + result.message());
            } else if result is mongodb:ApplicationError {
                return error("Application error: " + result.message());
            } else {
                return error("No pickup request found for the given user and request ID.");
            }
        } else if authHeaderResult is http:HeaderNotFoundError {
            return error("Authorization header is missing");
        } else {
            return error("Authorization header is invalid");
        }
    }

    //get all requests pending, scheduled, completed for user
    resource function get pendingRequests(http:Caller caller, http:Request req) returns error? {
        string|http:HeaderNotFoundError authHeaderResult = req.getHeader("Authorization");

        if authHeaderResult is string && authHeaderResult.startsWith("Bearer ") {
            string token = authHeaderResult.substring(7);
            string userId = check decodeToken(token);

            mongodb:Collection pickupRequestsCollection = check self.db->getCollection("PickupRequests");

            map<json> filter = {"userId": userId, "status": "PENDING"};

            var result = pickupRequestsCollection->find(filter, {}, {}, PickupRequest);

            if result is stream<PickupRequest, error?> {
                PickupRequest[] pendingRequests = [];

                error? e = result.forEach(function(PickupRequest request) {
                    pendingRequests.push(request);
                });

                if e is error {
                    return error("Error occurred while processing results: " + e.message());
                }

                check result.close();

                check caller->respond(pendingRequests);
            } else if result is mongodb:DatabaseError {
                return error("Database error: " + result.message());
            } else if result is mongodb:ApplicationError {
                return error("Application error: " + result.message());
            } else {
                return error("Unexpected error occurred while fetching data");
            }
        } else if authHeaderResult is http:HeaderNotFoundError {
            return error("Authorization header is missing");
        } else {
            return error("Authorization header is invalid");
        }
    }

    resource function get scheduledRequests(http:Caller caller, http:Request req) returns error? {
        string|http:HeaderNotFoundError authHeaderResult = req.getHeader("Authorization");

        if authHeaderResult is string && authHeaderResult.startsWith("Bearer ") {
            string token = authHeaderResult.substring(7);
            string userId = check decodeToken(token);

            mongodb:Collection pickupRequestsCollection = check self.db->getCollection("PickupRequests");

            map<json> filter = {"userId": userId, "status": "SCHEDULED"};

            var result = pickupRequestsCollection->find(filter, {}, {}, PickupRequest);

            if result is stream<PickupRequest, error?> {
                PickupRequest[] pendingRequests = [];

                error? e = result.forEach(function(PickupRequest request) {
                    pendingRequests.push(request);
                });

                if e is error {
                    return error("Error occurred while processing results: " + e.message());
                }

                check result.close();

                check caller->respond(pendingRequests);
            } else if result is mongodb:DatabaseError {
                return error("Database error: " + result.message());
            } else if result is mongodb:ApplicationError {
                return error("Application error: " + result.message());
            } else {
                return error("Unexpected error occurred while fetching data");
            }
        } else if authHeaderResult is http:HeaderNotFoundError {
            return error("Authorization header is missing");
        } else {
            return error("Authorization header is invalid");
        }
    }

    resource function get completedRequests(http:Caller caller, http:Request req) returns error? {
        string|http:HeaderNotFoundError authHeaderResult = req.getHeader("Authorization");

        if authHeaderResult is string && authHeaderResult.startsWith("Bearer ") {
            string token = authHeaderResult.substring(7);
            string userId = check decodeToken(token);

            mongodb:Collection pickupRequestsCollection = check self.db->getCollection("PickupRequests");

            map<json> filter = {"userId": userId, "status": "COMPLETED"};

            var result = pickupRequestsCollection->find(filter, {}, {}, PickupRequest);

            if result is stream<PickupRequest, error?> {
                PickupRequest[] pendingRequests = [];

                error? e = result.forEach(function(PickupRequest request) {
                    pendingRequests.push(request);
                });

                if e is error {
                    return error("Error occurred while processing results: " + e.message());
                }

                check result.close();

                check caller->respond(pendingRequests);
            } else if result is mongodb:DatabaseError {
                return error("Database error: " + result.message());
            } else if result is mongodb:ApplicationError {
                return error("Application error: " + result.message());
            } else {
                return error("Unexpected error occurred while fetching data");
            }
        } else if authHeaderResult is http:HeaderNotFoundError {
            return error("Authorization header is missing");
        } else {
            return error("Authorization header is invalid");
        }
    }

    // Delete a pickup request by ID
    resource isolated function delete deleteRequest/[string requestId](http:Caller caller, http:Request req) returns error? {
        string|http:HeaderNotFoundError authHeaderResult = req.getHeader("Authorization");

        if authHeaderResult is string && authHeaderResult.startsWith("Bearer ") {
            string token = authHeaderResult.substring(7);
            string userId = check decodeToken(token);
            io:println("Deleting Pickup Request with ID: ", requestId);

            mongodb:Collection pickupRequestsCollection = check self.db->getCollection("PickupRequests");

            // Define the filter to find the request by ID and the userId
            map<json> filter = {
                "id": requestId,
                "userId": userId
            };

            // Attempt to delete the request
            var result = pickupRequestsCollection->deleteOne(filter);

            if result is mongodb:DeleteResult {
                if result.deletedCount > 0 {
                    // Successfully deleted
                    check caller->respond("Pickup request deleted successfully.");
                } else {
                    // No documents matched the filter
                    return error("No pickup request found with the specified ID for the user.");
                }
            } else if result is mongodb:DatabaseError {
                return error("Database error: " + result.message());
            } else if result is mongodb:ApplicationError {
                return error("Application error: " + result.message());
            } else {
                return error("Unexpected error occurred while deleting the request.");
            }
        } else if authHeaderResult is http:HeaderNotFoundError {
            return error("Authorization header is missing");
        } else {
            return error("Authorization header is invalid");
        }
    }

}

isolated function decodeToken(string token) returns string|error {
    [jwt:Header, jwt:Payload] result = check jwt:decode(token);
    return result[1]["sub"].toString();
};
