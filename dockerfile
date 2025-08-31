#use the official .NET Core runtime as a parent image
#FROM mcr.microsoft.com/dotnet/core/aspnet:3.1-buster-slim AS base
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build

#Set the working directory to/app
WORKDIR /usr/src/app

#Copy the contents of the publishhed folder into the container"
COPY . .

#Expose port 80 for the application
EXPOSE 80
EXPOSE 443

# Set the environment variable to configure the listening URL
ENV ASPNETCORE_URLS=http://0.0.0.0:80

#Define the entro point for the application
ENTRYPOINT ["dotnet", "Agent.dll"]
