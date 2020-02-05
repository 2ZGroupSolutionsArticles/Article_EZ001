![img2](https://github.com/2ZGroupSolutionsArticles/Article_EZ001/blob/master/Images/header.jpg)
<br>

# How to sign a URLRequest and download a file from S3 in iOS.

Let’s talk about downloading files from AWS S3 in iOS mobile Apps.

AWS has a batch of [services](https://aws.amazon.com/mobile/) which we can use with our mobile applications. All this can be controlled in developer console with separate Mobile Hub. Also, it has [iOS SDK](https://github.com/aws/aws-sdk-ios) to make the developers life a bit easier. Actually sometimes not, but it’s another story. Usually, it’s enough to use it from the box as is to achieve the result and have the most popular and common solutions in the Apps.

So if you want to communicate with S3 in a usual manner and download/upload files, I highly recommend using official [AWS SDK for iOS](https://github.com/aws/aws-sdk-ios).

But what if we have some restrictions, don’t want to add AWSS3 to our project just to download once a single file or we need to have URLRequest and download something with it.

We have a few options in this case. The easiest one is to make a required file public in a bucket. Such file will be visible for all who have the correct link. But it’s not secure, and such approach very depends on our needs and type of content. Yes, we can still have a unique and ugly link, so nobody will just guess it. But better to use every possible solution to make content secure and make our user feel safe especially when we can get this just out from the AWS box.

Let’s create signed request to get a non-public image from our S3 bucket.<br>
AWS uses Signature V4 so that we will use it. But old regions can still support Signature V2, if they were created until 10 Jan 2014, according to official documentation.

At the beginning we need S3. I propose to create it without help from Mobile Hub side.
Just [skip](https://github.com/2ZGroupSolutionsArticles/Article_001#implement-urlrequest-signing-in-ios) this section if you’re familiar with AWS and this process.


## Setup AWS

I assume that you already have AWS developer account. Or you can create one for testing. AWS has [free tiers](https://aws.amazon.com/free/), and it’s enough for experimenting with various ideas, learning or even MVP. 

We need to select S3 service from the list of services.
![img1](https://github.com/2ZGroupSolutionsArticles/Article_EZ001/blob/master/Images/img1.jpg)<br><br>

Now we can create a new bucket for testing.
Let’s call it **downloadimagetestbucket**. We can keep all settings by default for now.
![img2](https://github.com/2ZGroupSolutionsArticles/Article_EZ001/blob/master/Images/img2.jpg)<br><br>

We have storage, so let’s upload our test image. Keep all default settings for it, to be sure that it’s not public.
![img3](https://github.com/2ZGroupSolutionsArticles/Article_EZ001/blob/master/Images/img3.jpg)<br><br>

We need AWS credentials to generate request signature. We can use access key ID and secret generated for our root account. But it can be not a good idea, especially if you’re an owner. Such credentials will have full access to everything. We can use them for fast experiments, but not for real life Apps. We will create separate [IAM](https://aws.amazon.com/iam/) user only with access to our test bucket. 

As before from AWS console with all services list select IAM.
From “Users” tab we can add a new user.
![img4](https://github.com/2ZGroupSolutionsArticles/Article_EZ001/blob/master/Images/img4.jpg)<br><br>

A mythical person with name **downloadimagetestuser** and **Programmatic access**.
![img5](https://github.com/2ZGroupSolutionsArticles/Article_EZ001/blob/master/Images/img5.jpg)<br><br>

And then just next… next… next and create. Do not forget to save ID and secret.<br>
We have the user without any permissions, and he can do nothing in our AWS. Absolutely useless person.

Let’s teach him some tricks. We need to add permission to access S3.

For that, we’ll create separate policy from the Policies tab.
![img6](https://github.com/2ZGroupSolutionsArticles/Article_EZ001/blob/master/Images/img6.jpg)<br><br>

We can play with a visual editor, but sometimes with JSON, it can be much faster. But in this case we should know what are we doing; otherwise it won’t work or even validated.

We will grant only read objects from our S3. You can find more actions in [official documentation](https://docs.aws.amazon.com/AmazonS3/latest/dev/using-with-s3-actions.html). Also, we need our bucket ARN to allow access only to it. You can select S3 bucket and copy it from info.

JSON looks like
``` json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "65487465138798",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject"
            ],
            "Resource": "arn:aws:s3:::downloadimagetestbucket/*"
        }
    ]
}
```

Let’s name it **downloadimagetestbucketpolicy**. You can add some description too. And then create it. 
Now we should go back to our created useless user. Select it and in the permission tab select *Add permissions*.
![img7](https://github.com/2ZGroupSolutionsArticles/Article_EZ001/blob/master/Images/img7.jpg)<br><br>

Select *Attach existing policies directly* and filter by policy name.
Attach the test policy to the user.
![img8](https://github.com/2ZGroupSolutionsArticles/Article_EZ001/blob/master/Images/img8.jpg)<br><br>

Now with this permission, we can use our user.

## Implement URLRequest signing in iOS

For creating a request, we will need
+ File URL, we can find it by selecting the file from our bucket.
+ IAM user access key ID and secret, we saved them when created new user.
+ Bucket region, region name is visible when we are selecting the bucket from S3, list of [all regions](https://docs.aws.amazon.com/general/latest/gr/rande.html) in Amazon S3 section. We will need string like **us-east-1**.

Some info from the official documentation.
+ How to get an object from S3. [Link](https://docs.aws.amazon.com/AmazonS3/latest/API/RESTObjectGET.html)
+ About Authenticating request. [Link](https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-authenticating-requests.html)
+ How to calculate a signature. [Link](https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html)

The idea is pretty simple. We have some request. We calculate signature string from it using user’s secret and passing user’s ID with the request. AWS will use this ID to find the user and will use the same secret to calculate the signature. And then compare it with the signature from the request. Everything will be OK if it’s the same.

Signature depends on HTTP headers, so let's add some before actual calculating of the signature.

1) We will need a SHA256 hash string in hex encoding for the payload; we download a file, so will use empty Data with 0 bytes.
Place it with `x-amz-content-sha256` header.

2) Add `Content-Type` header with `image/png` string in our case.

3) `Host` field which contains service name + region + *amazonaws.com*

    Template `(serviceName).(region).amazonaws.com`

    Will looks like `s3.us-east1.amazonaws.com`

4) `X-Amz-Date` date with string format **yyyyMMdd’T’HHmmss’Z’**. Use GMT zone and en_US_POSIX locale for all date strings. Save date somewhere; we will need the same timestamp in a few places.

5) The last field is auth `Authorization`. It contains signature algorithm, credentials, signed headers and the signature itself.

    Template `AWS4-HMAC-SHA256 Credential=(requestCredentials) SignedHeaders=(signedHeaders) Signature=(signature)`

    Will looks like `AWS4-HMAC-SHA256 Credential=AXXXXF6YJEKB2NFZXXXX/20181009/us-east-1/s3/aws4_request, SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date, Signature=d3402ed5d4d46cea0b3c17e78c421a8afce0a58fd01f24dd77dfb06893613445`
    
### Creating the credentials string
The string contains access key ID and request scope.<br>
Template `(accessKeyID)/(requestScope)`

Request scope contains
+ Date string in short format `yyyyMMdd`.
+ Our region.
+ Service name, s3 in our case.
+ And a terminator `aws4_request`.

We will need the request scope for calculating the signature too.

Scope template `(dateString)/(region)/(serviceName)/(terminator)`

Will looks like `20181009/us-east-1/s3/aws4_request`<br><br>

Full template `(accessKeyID)/(dateString)/(reion)/(serviceName)/(terminator)`

Will looks like `AXXXXF6YJEKB2NFZXXXX/20181009/us-east-1/s3/aws4_request`

###  Creating signed headers string. 
Should contain all headers which we use for calculating the signature.

We need all HTTP fields names from the request, sort them alphabetically in a case-insensitive way and enumerate them with semicolon separator. Headers should be lowercased. And we will use HTTP headers few times, and each time they should be sorted.

Template `(header);(header)`

Will looks like `content-type;host;x-amz-content-sha256;x-amz-date`


###  Calculating the signature
As we see in [documentation](https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html) steps to calculate the signature
1) Create canonical request string 
2) Create StringToSign string 
2) Calculate the signature

#### Creating canonical request string
Each section should be with a new line `\n`<br>

It contains
1) HTTP method, `GET` in our case.
2) URL encoded path `/downloadimagetestbucket/TestImage.png`.
3) Then goes canonical query string, but it unnecessary for now, so just newline `\n`.
4) Canonical headers string

    As usually should be sorted by lowercased name. Should contain the header name and value separated with a new line `\n`. And should not contain extra whitespaces.

    Template `(headerName1):(headerValue1)\n(headerName2):(headerValue2)`

    Looks like `content-type:image/png\nhost:s3.us-east-1.amazonaws.com\nx-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nx-amz-date:20181009T115731Z\n`

5) Signed headers string, same as we constructed before.
6) SHA256 hash string in hex encoding for the request payload, also was calculated before for Data with 0 bytes. We can just reuse it.

Final canonical request string for our test app will look like
`GET\n/downloadimagetestbucket/TestImage.png\n\ncontent-type:image/png\nhost:s3.us-east-1.amazonaws.com\nx-amz-content-sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\nx-amz-date:20181009T115731Z\n\ncontent-type;host;x-amz-content-sha256;x-amz-date\ne3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`

#### Creating StringToSign string
As for the canonical request, each section should be with a new line `\n`.

It contains
1) AWS signature algorithm `AWS4-HMAC-SHA256`.
2) Date in ISO8601 format **yyyyMMdd’T’HHmmss’Z’**, we used it before.
3) Request scope which we used before too. Will looks like `20181009/us-east-1/s3/aws4_request`
4) SHA256 string in hex encoding from our constructed canonical request string

Template
`AWS4-HMAC-SHA256\n(dateStringISO8601)\n(requestScope)\n(hexEncodedSHA256CanonicalRequestString)`

Final StringToSign will looks like
`AWS4-HMAC-SHA256\n20181009T115731Z\n20181009/us-east-1/s3/aws4_request\n61c352d185e6349d274da84ec475138061572f59d6dbecfcfb7f12fd4c5ce36f`

#### Calculating the signature
As we saw before AWS uses the HMAC-SHA256 algorithm, we can use the CommonCrypto framework or any third party solution to make our life a bit simpler.

Each next step is nested encryption of data with previously generated keys with HMAC-SHA256.

1) Create *DateKey*. Encrypt date string in short format **yyyyMMdd** with secret key in format `AWS4(secretKey)`
2) Create *DateRegionKey*. Encrypt region string with previously created key *DateKey*.
3) Create *DateRegionServiceKey*. Encrypt service name `s3` in our case with created key *DateRegionKey*.
4) Create *SigningKey*. Encrypt terminator `aws4_request` with created *DateRegionServiceKey*.
5) Create final hex encoded Signature string. Encrypt created before *StringToSign* with *SigningKey*.<br><br>

And that's all. Now we have everything for `Authorization` HTTP header. We can download our file from S3.<br><br>

You can check the [demo project](https://github.com/2ZGroupSolutionsArticles/Article_001/tree/master/AWSS3DownloadFileDemo). It’s just an example, recommend not to use it as is because used force unwrapping in some places, but you can adopt this solution for your specific needs and in a more safe manner.<br><br>

### Author
Yevhenii(Eugene) Zozulia

Email: yevheniizozulia@2zgroup.net

LinkedIn: [EugeneZI](https://www.linkedin.com/in/eugenezi/)
