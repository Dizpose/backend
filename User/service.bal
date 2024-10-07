import ballerina/http;
import ballerina/uuid;
import ballerina/jwt;
import ballerinax/mongodb;
import ballerina/crypto;

configurable string host = ?;
configurable int port = ?;

configurable string username = ?;
configurable string password = ?;
configurable string database = ?;

configurable string secret_key = "TZiq/jhpastYzsB7F042qlg/n5BjUvIur76i5O1Z4iw=";

configurable string privateKeyFile = "resources/private.key";

// MongoDB client setup
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
        allowMethods: ["GET", "POST", "OPTIONS","PUT", "DELETE"]
    }
}

service /users on new http:Listener(9090) {
    private final mongodb:Database db;

    function init() returns error? {
        self.db = check mongoDb->getDatabase("DizposeDB");
    }

    // User registration
    resource function post register(UserInput input) returns string|error {
        mongodb:Collection usersCollection = check self.db->getCollection("Users");
        string userId = uuid:createType1AsString();

        // Hash the password before saving to the DB
        string dataString = input.password;
        byte[] data = dataString.toBytes();
        byte[] hashedData = crypto:hashSha256(data);
        string hashedPassword = hashedData.toBase64();

        User user = {
            id: userId,
            name: input.name,
            email: input.email,
            phone: input.phone,
            password: hashedPassword
            //roles: input.roles
        };

        check usersCollection->insertOne(user);
        return string `User ${input.name} registered successfully`;
    }

    // User login 
    
    resource function post login(LoginInput input) returns json|error {
        mongodb:Collection usersCollection = check self.db->getCollection("Users");

        stream<User, error?> resultStream = check usersCollection->find({
            email: input.email
        });

        record {User value;}|error? result = resultStream.next();

        if result is error? {
            return error(string `Invalid credentials: User with email ${input.email} not found.`);
        }

        User user = result.value;

        string inputPasswordHashed = crypto:hashSha256(input.password.toBytes()).toBase64();

        // Verify password
        if user.password != inputPasswordHashed {
            return error("Invalid credentials: Incorrect password.");
        }

        jwt:IssuerConfig issuerConfig = {
            username: user.id,
            issuer: "buddhi",
            audience: "user-service",
            expTime: 2592000,
            signatureConfig: {
                config: {
                    keyFile: privateKeyFile
                }
            }
        };

        //issue jwt
        string jwtToken = check jwt:issue(issuerConfig);


        return {message: "Login successful", token: jwtToken, user: {id: user.id, name: user.name, email: user.email, phone: user.phone }};
    }

    @http:ResourceConfig {
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

    // Get user by ID
    resource function get [string id]() returns User|error {
        mongodb:Collection usersCollection = check self.db->getCollection("Users");

        stream<User, error?> resultStream = check usersCollection->find({
            id: id
        });

        record {User value;}|error? result = resultStream.next();

        if result is error? {
            return error(string `Cannot find the user with id: ${id}`);
        }
        return result.value;
    }

    @http:ResourceConfig {
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

    // Update user by ID
    resource function put [string id](UserInput input) returns string|error {
    mongodb:Collection usersCollection = check self.db->getCollection("Users");

    // Create a map to store the fields to update
    map<string> updateFields = {};

    // Update name if provided
    if input.name != "" {
        updateFields["name"] = input.name;
    }

    // Update email if provided
    if input.email != "" {
        updateFields["email"] = input.email;
    }

    // Update phone if provided
    if input.phone != "" {
        updateFields["phone"] = input.phone;
    }

    // Update password if provided (hash it before storing)
    if input.password != "" {
        updateFields["password"] = input.password;
    }

    // Ensure there are fields to update
    if updateFields.length() == 0 {
        return error("No fields provided for update.");
    }

    // Proceed to update the user document in the database
    var updateResult = check usersCollection->updateOne(
        {"id": id},  // Filter by user ID
        {"set": updateFields}  // Set only the fields that were provided
    );

    if updateResult.matchedCount > 0 {
        return string `User ${id} updated successfully.`;
    } else {
        return error("User not found or no updates made.");
    }
}

    @http:ResourceConfig {
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

    // Delete user by ID
    resource function delete [string id]() returns string|error {
        mongodb:Collection usersCollection = check self.db->getCollection("Users");

        var deleteResult = check usersCollection->deleteOne({"id": id});

        if deleteResult.deletedCount > 0 {
            return string `User ${id} deleted successfully.`;
        } else {
            return error("User not found.");
        }
    }
}

// Define input types
type UserInput record {
    string name;
    string email;
    string phone;
    string password;
    //string[] roles;
};

type LoginInput record {
    string email;
    string password;
};

// Define the User type
type User record {
    string id;
    string name;
    string email;
    string phone;
    string password;
    // Stored as a hashed value
    //string[] roles;
};
