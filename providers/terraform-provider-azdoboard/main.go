package main

import (
	"context"
	"log"

	"github.com/alexharvey/terraform-provider-azdoboard/internal/provider"
	"github.com/hashicorp/terraform-plugin-framework/providerserver"
)

func main() {
	err := providerserver.Serve(
		context.Background(),
		provider.New,
		providerserver.ServeOpts{
			Address: "registry.terraform.io/local/azdoboard",
		},
	)
	if err != nil {
		log.Fatal(err)
	}
}
