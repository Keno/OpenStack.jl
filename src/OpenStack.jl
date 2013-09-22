module OpenStack

    import WWWClient
    using URIParser
    using JSON

    export identify, createServer, flavors, IdentityEndpoint, Token, Flavor, Image, Network, servers, Server, ips, status, wait_active

    abstract Endpoint

    immutable IdentityEndpoint <: Endpoint
        uri::URI
    end
    IdentityEndpoint(s) = IdentityEndpoint(URI(s))

    immutable NovaEndpoint <: Endpoint
        uri::URI
    end
    NovaEndpoint(s) = NovaEndpoint(URI(s))  

    endpoint(ep::IdentityEndpoint,endpoint) = URI(ep.uri,path=string(ep.uri,"/",endpoint))
    endpoint(ep::NovaEndpoint,endpoint) = URI(ep.uri,path=string(ep.uri,"/",endpoint))

    immutable Token
        token::String
    end

    immutable FlavorDetail
        ram::Int
        disk::Int
        vcpus::Int
    end

    immutable Flavor
        id::ASCIIString
        name::ASCIIString
        detail::FlavorDetail
        Flavor(id,name) = new(id,name)
        Flavor(id,name,ram,disk,vcpus) = new(id,name,FlavorDetail(ram,disk,vcpus))
    end

    immutable Image
        id
    end

    immutable Network
        id
    end

    immutable Server 
        id::ASCIIString
        name::ASCIIString
    end

    function post(nova::NovaEndpoint,path,token::Token,data)
       JSON.parse(WWWClient.post(endpoint(nova,path),json(data);
        headers = {"Content-type"=>"application/json","Accept"=>"application/json","X-Auth-Token"=>token.token}).data)
    end

    function get(nova::NovaEndpoint,path,token::Token)
       JSON.parse(WWWClient.get(endpoint(nova,path);
        headers = {"Content-type"=>"application/json","Accept"=>"application/json","X-Auth-Token"=>token.token}).data)
    end

    function identify(ep::IdentityEndpoint,username,password,tenantID)
        data = JSON.parse(WWWClient.post(endpoint(ep,"tokens"),json({
            "auth" => {
                "passwordCredentials" => {
                    "username" => username,
                    "password" => password
                },
                "tenantId" => tenantID
            }
        });headers = {"Content-type"=>"application/json","Accept"=>"application/json"}).data)
        token = Token(data["access"]["token"]["id"])
        endpoints = (Symbol=>Endpoint)[]
        for x in data["access"]["serviceCatalog"]
            if x["name"] == "nova"
                endpoints[:nova] = NovaEndpoint(x["endpoints"][1]["publicURL"])
            end
        end
        (token,endpoints)
    end

    function createServer(nova::NovaEndpoint,token::Token,image::Image,flavor::Flavor,name::String;networks=[],keyname="")
        data = { 
            "server" => {
                "flavorRef" => flavor.id,
                "imageRef" => image.id,  
                "name" => name,
                "networks" => networks,
                "metadata" => Dict{String,Any}()
            }
        }
        if !isempty(keyname)
            data["server"]["key_name"] = keyname
        end
        println(json(data))
        Server(post(nova,"/servers",token,data)["server"]["id"],name)
    end

    function flavors(nova::NovaEndpoint,token::Token)
        data = get(nova,"/flavors",token)
        ret = Flavor[]
        for flavor in data["flavors"]
            push!(ret,Flavor(flavor["id"],flavor["name"]))
        end
        ret
    end

    function servers(nova,token;params...)
        data = get(nova,"/servers$(WWWClient.encode_params(params))",token)
        ret = Server[]
        for server in data["servers"]
            push!(ret,Server(server["id"],server["name"]))
        end
        ret
    end

    function ips(nova::NovaEndpoint,token::Token,server)
        data = get(nova,"/servers/$(server.id)/ips",token)
        ret = Base.IpAddr[]
        for ip in data["addresses"]["inet"]
            push!(ret,parseip(ip["addr"]))
        end
        ret
    end

    function ips(nova::NovaEndpoint,token::Token,server,netname::ASCIIString)
        data = get(nova,"/servers/$(server.id)/ips",token)
        ret = Base.IpAddr[]
        done = false
        for (name,net) in data["addresses"]
            if name != netname
                continue
            end
            for ip in net
                push!(ret,parseip(ip["addr"]))
            end
            done = true
            break
        end
        if !done
            error("Instance is not part of network")
        end
        ret
    end

    function status(nova::NovaEndpoint,token::Token,server)
        data = get(nova,"/servers/$(server.id)",token)
        data["server"]["status"]
    end

    function wait_active(nova::NovaEndpoint,token::Token,server;interval=5.0)
        while status(nova,token,server) != "ACTIVE"
            sleep(interval)
        end
    end

end # module
