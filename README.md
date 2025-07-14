# Microsoft WordPress on Azure (Bicep)

Defines Azure resources in Bicep (using [Azure Verified Modules](https://aka.ms/AVM)) to deploy the Microsoft WordPress container image.

## Benefits

This deployment is based on the [Azure Marketplace offering](https://portal.azure.com/#view/Microsoft_Azure_Marketplace/GalleryItemDetailsBladeNopdl/id/WordPress.WordPress/selectionMode~/false/resourceGroupId//resourceGroupLocation//dontDiscardJourney~/false/selectedMenuId/home/launchingContext~/%7B%22galleryItemId%22%3A%22WordPress.WordPress%22%2C%22source%22%3A%5B%22GalleryFeaturedMenuItemPart%22%2C%22VirtualizedTileDetails%22%5D%2C%22menuItemId%22%3A%22home%22%2C%22subMenuItemId%22%3A%22Search%20results%22%2C), but has the following improvements:

- No hardcoded values/references in the template.
- Uses Azure Verified Modules.
- Stores secrets in Key Vault.
- Uses private endpoints for Storage and Key Vault.

## Future enhancements

- Restrict App Service to accept connections only from Front Door.
- Custom email domain

## Other differences

- No custom Portal UI

## References

<https://github.com/Azure/wordpress-linux-appservice>

## After deployment steps

1. Activate the WordPress plugins.
1. Ensure a custom email domain (if specified) is configured.
