package memeland

import (
    "sort"
    "std"
    "strconv"
    "strings"
    "time"

    "gno.land/p/demo/avl"
    "gno.land/p/demo/ownable"
    "gno.land/p/demo/seqid"
)

type Post struct {
    ID            string
    Data          string
    Author        std.Address
    Timestamp     time.Time
    UpvoteTracker *avl.Tree 
}

type Memeland struct {
    *ownable.Ownable
    Posts       []*Post
    MemeCounter seqid.ID
}

func NewMemeland() *Memeland {
    return &Memeland{
        Ownable: ownable.New(),
        Posts:   make([]*Post, 0),
    }
}

func (m *Memeland) PostMeme(data string, timestamp int64) string {
    if data == "" || timestamp <= 0 {
        panic("timestamp or data cannot be empty")
    }

    id := m.MemeCounter.Next().String()

    newPost := &Post{
        ID:            id,
        Data:          data,
        Author:        std.PrevRealm().Addr(),
        Timestamp:     time.Unix(timestamp, 0),
        UpvoteTracker: avl.NewTree(),
    }

    m.Posts = append(m.Posts, newPost)
    return id
}

func (m *Memeland) Upvote(id string) string {
    post := m.getPost(id)
    if post == nil {
        panic("post with specified ID does not exist")
    }

    caller := std.PrevRealm().Addr().String()

    if _, exists := post.UpvoteTracker.Get(caller); exists {
        panic("user has already upvoted this post")
    }

    post.UpvoteTracker.Set(caller, struct{}{})

    return "upvote successful"
}

func (m *Memeland) GetPostsInRange(startTimestamp, endTimestamp int64, page, pageSize int, sortBy string) string {
    if len(m.Posts) == 0 {
        return "[]"
    }

    if page < 1 {
        panic("page count cannot be less than 1")
    }

    if pageSize < 1 {
        panic("page size cannot be less than 1")
    }


    if pageSize > 10 {
        panic("page size cannot be larger than 10")
    }

    var filteredPosts []*Post

    start := time.Unix(startTimestamp, 0)
    end := time.Unix(endTimestamp, 0)

    for _, p := range m.Posts {
        if !p.Timestamp.Before(start) && !p.Timestamp.After(end) {
            filteredPosts = append(filteredPosts, p)
        }
    }

    switch sortBy {
    case "UPVOTES":
        dateSorter := PostSorter{
            Posts: filteredPosts,
            LessF: func(i, j int) bool {
                return filteredPosts[i].UpvoteTracker.Size() > filteredPosts[j].UpvoteTracker.Size()
            },
        }
        sort.Sort(dateSorter)
    default:
        dateSorter := PostSorter{
            Posts: filteredPosts,
            LessF: func(i, j int) bool {
                return filteredPosts[i].Timestamp.After(filteredPosts[j].Timestamp)
            },
        }
        sort.Sort(dateSorter)
    }

    startIndex := (page - 1) * pageSize
    endIndex := startIndex + pageSize

    if startIndex >= len(filteredPosts) {
        return "[]"
    }

    if endIndex > len(filteredPosts) {
        endIndex = len(filteredPosts)
    }
    return PostsToJSONString(filteredPosts[startIndex:endIndex])
}

func (m *Memeland) RemovePost(id string) string {
    if id == "" {
        panic("id cannot be empty")
    }

    if err := m.CallerIsOwner(); err != nil {
        panic(err)
    }

    for i, post := range m.Posts {
        if post.ID == id {
            m.Posts = append(m.Posts[:i], m.Posts[i+1:]...)
            return id
        }
    }

    panic("post with specified id does not exist")
}

func PostsToJSONString(posts []*Post) string {
    var sb strings.Builder
    sb.WriteString("[")

    for i, post := range posts {
        if i > 0 {
            sb.WriteString(",")
        }

        sb.WriteString(PostToJSONString(post))
    }
    sb.WriteString("]")

    return sb.String()
}
func PostToJSONString(post *Post) string {
    var sb strings.Builder

    sb.WriteString("{")
    sb.WriteString(`"id":"` + post.ID + `",`)
    sb.WriteString(`"data":"` + escapeString(post.Data) + `",`)
    sb.WriteString(`"author":"` + escapeString(post.Author.String()) + `",`)
    sb.WriteString(`"timestamp":"` + strconv.Itoa(int(post.Timestamp.Unix())) + `",`)
    sb.WriteString(`"upvotes":` + strconv.Itoa(post.UpvoteTracker.Size()))
    sb.WriteString("}")

    return sb.String()
}
func escapeString(s string) string {
    return strings.ReplaceAll(s, `"`, `\"`)
}

func (m *Memeland) getPost(id string) *Post {
    for _, p := range m.Posts {
        if p.ID == id {
            return p
        }
    }

    return nil
}

type PostSorter struct {
    Posts []*Post
    LessF func(i, j int) bool
}

func (p PostSorter) Len() int {
    return len(p.Posts)
}

func (p PostSorter) Swap(i, j int) {
    p.Posts[i], p.Posts[j] = p.Posts[j], p.Posts[i]
}

func (p PostSorter) Less(i, j int) bool {
    return p.LessF(i, j)
}

